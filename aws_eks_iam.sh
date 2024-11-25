#!/bin/bash

log_message() {
	local MESSAGE=$1
	echo "$(date '+%Y-%m-%d %H:%M:%S') - $MESSAGE"
}

check_cluster_authentication_mode() {
	local REGION=$1
	local CLUSTER_NAME=$2

	AUTH_MODE=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" --query "cluster.accessConfig.authenticationMode" --output text)

	if [ "$AUTH_MODE" == "CONFIG_MAP" ]; then
		return 1
	else
		return 0
	fi
}

add_permissions_to_clusters_in_region() {
	local REGION=$1
	local PRINCIPAL_ARN=$2
	local POLICY_ARN="arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

	log_message "Processing region: $REGION"

	CLUSTERS=$(aws eks list-clusters --region "$REGION" --query "clusters" --output text)

	for CLUSTER_NAME in $CLUSTERS; do
		log_message "Processing cluster: $CLUSTER_NAME in region: $REGION"

		if ! check_cluster_authentication_mode "$REGION" "$CLUSTER_NAME"; then
			log_message "Skipping cluster $CLUSTER_NAME in region $REGION as it is only accessible via CONFIG_MAP"
			continue
		fi

		OUTPUT=$(aws eks create-access-entry --region "$REGION" --cluster-name "$CLUSTER_NAME" --principal-arn "$PRINCIPAL_ARN" --type STANDARD 2>&1)
		if [ $? -ne 0 ]; then
			if echo "$OUTPUT" | grep -q "ResourceInUseException"; then
				log_message "Warning: Access entry already exists for cluster: $CLUSTER_NAME in region: $REGION"
			elif echo "$OUTPUT" | grep -q "InvalidRequestException"; then
				log_message "Error: Invalid request for cluster: $CLUSTER_NAME in region: $REGION - $OUTPUT"
			else
				log_message "Error: Failed to create access entry for cluster: $CLUSTER_NAME in region: $REGION - $OUTPUT"
				continue
			fi
		fi

		OUTPUT=$(aws eks associate-access-policy --region "$REGION" --cluster-name "$CLUSTER_NAME" --principal-arn "$PRINCIPAL_ARN" --access-scope type=cluster --policy-arn "$POLICY_ARN" 2>&1)
		if [ $? -ne 0 ]; then
			log_message "Error: Failed to associate access policy for cluster: $CLUSTER_NAME in region: $REGION - $OUTPUT"
			continue
		fi

		log_message "Permissions added to cluster: $CLUSTER_NAME in region: $REGION"
	done
}

ALL=false
SPECIFIC_REGION=""

while [[ $# -gt 0 ]]; do
	case $1 in
	--all)
		ALL=true
		shift
		;;
	--region)
		SPECIFIC_REGION=$2
		shift 2
		;;
	--principal-arn)
		PRINCIPAL_ARN=$2
		shift 2
		;;
	*)
		echo "Unknown argument: $1"
		exit 1
		;;
	esac
done

if [ -z "$PRINCIPAL_ARN" ]; then
	echo "Error: IAM principal ARN must be specified with --principal-arn."
	exit 1
fi

if $ALL; then
	REGIONS=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)
elif [ -n "$SPECIFIC_REGION" ]; then
	REGIONS=$SPECIFIC_REGION
else
	echo "Error: Either --all or --region must be specified."
	exit 1
fi

for REGION in $REGIONS; do
	add_permissions_to_clusters_in_region "$REGION" "$PRINCIPAL_ARN"
done

log_message "All specified regions and clusters processed."



# ./script.sh --region us-west-2 --principal-arn 

# ./script.sh --all --principal-arn 
