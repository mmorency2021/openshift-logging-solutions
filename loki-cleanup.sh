```bash
# Delete Loki stack CR ( instance)

echo "Delete Loki stack CR ( instance)"
oc -n $namespace delete -f create-lokistack-cr.yaml

# Delete grafana if present
echo "Check if grafana deployment is present then delete"

if oc get deployment "grafana" -n "$namespace" > /dev/null 2>&1; then
  echo "Grafana deployment found in $namespace namespace. Deleting..."
  #oc delete deployment "$deployment" -n "$namespace"
  oc -n "$namespace" delete -f integrate_loki_to_grafana.yaml
  oc -n "$namespace" delete -f create-clo-clf-cr.yaml
  #oc -n $namespace delete ClusterLogForwarder instance
else
  echo "Grafana deployment not found in $namespace namespace."
fi

while true; do
  check_pods
  if [ $? -eq 0 ]; then
    break
  fi
  sleep 10  # Adjust the sleep interval as needed
done

# Delete Loki Storage PVC
echo "Delete Loki Storge PVC"
oc -n $namespace get pvc |grep logging-loki|awk '{print $1}'|xargs oc -n $namespace delete pvc

# Delete loki secrets and obc
echo "Delete loki secrets and obc..."
oc -n $namespace delete secret lokistack-dev-odf
oc -n $namespace delete obc loki-bucket-odf
```
