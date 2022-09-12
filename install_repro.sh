#!/bin/bash

# This script will setup the repro as follows:
# 1. Create a kind cluster called cert-issue-repro
# 2. It will install cert manager
# 3. Create a self-signed CA cert and cluster issuer
# 4. Install Ingress Nginx
# 5. Configurate a few certificates and a test app to demonstrate the bug
# 6. Download the CA cert to facilitate curl without `-k` argument.

echo "Creating kind cluster"
kind create cluster --name cert-issue-repro --config=cluster-config.yaml

echo "Getting helm charts"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io

helm repo update

set +e
echo "Installing cert-manager"
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.9.1 \
  --set installCRDs=true
set -e

if [ ! -f certs/ca.crt ]; then
  echo "Creating cluster issuer with self-signed CA certificate"
  openssl req -nodes -new -x509 -sha256 -newkey rsa:2048 -subj "/CN=cluster-issuer.cluster.local/C=US/L=Seattle" -keyout certs/ca.key -out certs/ca.crt
fi

echo "Creating Root CA Cert Secret if it doesn't exist"
set +e
kubectl create secret tls root-ca-cert -n cert-manager --cert=certs/ca.crt --key=certs/ca.key

set -e
kubectl apply -f ca.yaml

echo "Provisioning demo certificates"
kubectl apply -f demo-certs.yaml

echo "Install Ingress Controller"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "Waiting for ingress controller to be available"
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout 120s

echo "Provisioning demo app"
kubectl apply -f hello-server.yaml

echo "Waiting for hello server to be available"
kubectl rollout status deployment/hello-server -n demo --timeout 120s

echo "Getting CA certificate for certs for testing with curl"
kubectl get secret -n demo hello-test-cert -o 'go-template={{ index .data "ca.crt" }}' | base64 --decode > certs/cacert.crt
