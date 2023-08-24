
# OpenShift Logging with Elasticsearch and Fluentd
## Deploy OpenShift Clogging Operator and Elasticsearch

- Create CLO Namespace  
01_clo_ns.yaml:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-logging 
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
```
```shellSession
$ oc apply -f 01_clo_ns.yaml
```
- Create CLO OperatorGroup 
02_clo_og.yaml:
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  targetNamespaces:
    - openshift-logging
```
```shellSession
$ oc apply -f 02_clo_client_og.yaml
```
- Create CLO and ES Subscription together  
03_clo_es_subs.yaml:
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging 
spec:
  channel: "stable" 
  name: cluster-logging
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: "elasticsearch-operator"
  namespace: "openshift-logging" 
spec:
  channel: "stable" 
  installPlanApproval: "Automatic" 
  source: "redhat-operators" 
  sourceNamespace: "openshift-marketplace"
  name: "elasticsearch-operator"
```
```shellSession
$ oc apply -f 03_clo_es_subs.yaml
```

## Create ClusterLogging CR with ES and Fluentd as type
Create CLO CR with logStore as elasticsearch and Collection type as fluentd
04_clo_cr.yaml:
```yaml
apiVersion: "logging.openshift.io/v1"
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  collection:
    logs:
      type: fluentd
      fluentd: {}
  curation:
    curator:
    schedule: 30 3 * * *
    type: curator
  logStore:
    type: elasticsearch
    elasticsearch:
      nodeCount: 6
      storage:
        storageClassName: "ocs-storagecluster-cephfs"
        size: 50G
      resources: 
        limits:
          memory: "4Gi"
        requests:
          memory: "4Gi"
      proxy: 
        resources:
          limits:
            memory: 256Mi
          requests:
             memory: 256Mi
      redundancyPolicy: SingleRedundancy
    retentionPolicy: 
      application:
        maxAge: 7d
      infra:
        maxAge: 7d
      audit:
        maxAge: 7d
  managementState: Managed
  visualization:
    type: kibana
    kibana:
      replicas: 1
```
```shellSession
$ oc apply -f 04_clo_cr.yaml
```


## Create CLO CLF 
- Start Create ClusterLoggingForwarder as elasticsearch  
05_clo_clf.yaml:
```yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  outputs:
    - name: internal-es
      type: elasticsearch
      secret:
        name: collector
      url: 'https://elasticsearch.openshift-logging.svc:9200'
  pipelines:
    - name: telco-logs
      inputRefs:
        - application
        - infrastructure
        - audit
      outputRefs:
        - internal-es
      labels:
        node: demo-migration
```
```shellSession
$ oc apply -f 05_clo_clf.yaml
```

## Access Kibana Gui 
https://kibana-openshift-logging.apps.abi.hubcluster-1.lab.eng.cert.redhat.com


## Links
https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.2?topic=administering-installing-configuring-cluster-logging

