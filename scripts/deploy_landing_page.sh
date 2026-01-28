#!/bin/bash
set -e

SOURCE_DIR="/home/adminuser/happynoises-v2"
KUBECONFIG_PATH="/home/adminuser/talos-vergeos-automation/kubeconfig"
MANIFEST_PATH="$SOURCE_DIR/kubernetes.yaml"

echo "Deploying Happy Noises Landing Page to Talos Cluster..."

# Ensure kubeconfig is used
export KUBECONFIG="$KUBECONFIG_PATH"

# Create ConfigMaps from files
echo "Creating ConfigMaps..."
kubectl delete configmap happynoises-landing-html happynoises-landing-css happynoises-landing-js happynoises-landing-logo happynoises-landing-nginx-conf --ignore-not-found
kubectl create configmap happynoises-landing-html --from-file=index.html="$SOURCE_DIR/index.html"
kubectl create configmap happynoises-landing-css --from-file=style.css="$SOURCE_DIR/style.css"
kubectl create configmap happynoises-landing-js --from-file=script.js="$SOURCE_DIR/script.js"
kubectl create configmap happynoises-landing-logo --from-file=logo.png="$SOURCE_DIR/logo.png"
kubectl create configmap happynoises-landing-nginx-conf --from-file=nginx.conf="$SOURCE_DIR/nginx.conf"

# Apply deployment and service
echo "Applying manifests..."
kubectl apply -f "$MANIFEST_PATH"

echo "Waiting for rollout..."
kubectl rollout status deployment/happynoises-landing

echo "Deployment complete! Application should be available on the cluster nodes."
