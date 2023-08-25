```bash
#!/bin/bash

set -e  # Exit on error
set -u  # Treat unset variables as errors

# Function to backup resources
backup_resources() {
    oc -n openshift-logging get "$1" "$2" -o yaml |
    yq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.generation, .metadata.creationTimestamp, .metadata.selfLink, .status)' > "cr-$2.yaml"
}

# Function to create a secret
create_secret() {
    oc -n openshift-logging create secret generic "$1" \
      --from-literal=access_key_id="${2}" \
      --from-literal=access_key_secret="${3}" \
      --from-literal=bucketnames="${4}" \
      --from-literal=endpoint="https://${5}:${6}"
}

# Function to check if all pods are fully up
check_pods_fully_up() {
    while true; do
        result=$(oc -n openshift-logging get po | awk 'match($2, /([0-9])+\/([0-9])+/, a) {if (a[1] < a[2]) print "NOK"}')

        if [ -z "$result" ]; then
            echo "All pods are fully up."
            break
        fi

        echo "Not all pods are fully up. Waiting..."
        sleep 5
    done
}

echo "Set clusterlogging to Unmanaged so this CR gets into Maintenance mode"
oc -n openshift-logging patch clusterlogging/instance -p '{"spec":{"managementState": "Unmanaged"}}' --type=merge
oc -n openshift-logging get clusterlogging instance

echo "Remove ClusterLogging OwnerReferences from Elasticsearch and Kibana Resources"
oc -n openshift-logging patch elasticsearch/elasticsearch -p '{"metadata":{"ownerReferences": []}}' --type=merge
oc -n openshift-logging patch kibana/kibana -p '{"metadata":{"ownerReferences": []}}' --type=merge

echo "Backup Elasticsearch and Kibana Resources"
backup_resources elasticsearch elasticsearch
backup_resources kibana kibana

echo "Delete Elasticsearch and Kibana Resources"
oc -n openshift-logging delete kibana/kibana elasticsearch/elasticsearch

echo "Create OBC S3 using ODF noobaa Storage"
oc -n openshift-logging apply -f loki-bucket-odf.yaml
# Wait for OBC to be in Bound status
while [[ "$(oc -n openshift-logging get obc loki-bucket-odf -o jsonpath='{.status.phase}')" != "Bound" ]]; do
    echo "Waiting for OBC to be Bound..."
    sleep 5
done

echo "OBC is now in Bound status"
oc -n openshift-logging get obc

echo "Get S3 Access info and Create lokistack secret"
BUCKET_HOST=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_HOST}')
BUCKET_NAME=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_NAME}')
BUCKET_PORT=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_PORT}')

ACCESS_KEY_ID=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
SECRET_ACCESS_KEY=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

create_secret lokistack-dev-odf "${ACCESS_KEY_ID}" "${SECRET_ACCESS_KEY}" "${BUCKET_NAME}" "${BUCKET_HOST}" "${BUCKET_PORT}"

echo "Create Loki stack CR ( instance)"
cat <<EOF | oc -n openshift-logging apply -f -
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.extra-small 
  storage:
    secret:
      name: lokistack-dev-odf
      type: s3
    tls:
      caName: openshift-service-ca.crt
  storageClassName: ocs-storagecluster-ceph-rbd
  tenants:
    mode: openshift-logging
EOF

echo "Create CLO CR as Vector type"
cat <<EOF | oc -n openshift-logging apply -f -
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  managementState: Managed
  logStore:
    type: lokistack
    lokistack:
      name: logging-loki
  collection:
    type: vector
EOF

# Sleep 10s to wait for PODs creating but not fully up e.g not 1/2
sleep 10

# Call the function to check pods
check_pods_fully_up

echo "Final check"
oc -n openshift-logging get pods,pvc,obc

echo "Please check openshift-console to see if loki logs are visible"
echo "If yes, then cleanup elasticsearch pvc after migration is successful done..."
echo "oc -n openshift-logging get pvc |grep elasticsearch|awk '{print \$1}'|xargs oc -n openshift-logging delete pvc"



```
