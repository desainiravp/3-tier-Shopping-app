#!/bin/bash

# Set variables
cluster_name=devops-eks-demo
region=ap-south-1
vpc_id=vpc-0f78407880a007a46
account_id=703671925616

# Step 1: Create EKS Cluster
eksctl create cluster \
  --name $cluster_name \
  --region $region \
  --zones ap-south-1a,ap-south-1b \
  --nodegroup-name devops-nodegroup \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed

# Step 2: Check node status
kubectl get nodes

# Step 3: Associate OIDC Provider
oidc_id=$(aws eks describe-cluster --name $cluster_name --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4
eksctl utils associate-iam-oidc-provider --cluster $cluster_name --approve

# Step 4: Install AWS Load Balancer Controller
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

eksctl create iamserviceaccount \
  --cluster=$cluster_name \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$account_id:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$cluster_name \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$region \
  --set vpcId=$vpc_id

kubectl get deployment -n kube-system aws-load-balancer-controller

# Step 5: Install EBS CSI Driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $cluster_name \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster $cluster_name \
  --service-account-role-arn arn:aws:iam::$account_id:role/AmazonEKS_EBS_CSI_DriverRole \
  --force

# Step 6: Clone and deploy app
git clone https://github.com/desainiravp/three-tier-architecture-demo.git
cd three-tier-architecture-demo/EKS/helm

kubectl create namespace robot-shop
helm install robot-shop . --namespace robot-shop

# Step 7: Validate Deployment
kubectl get all -n robot-shop
kubectl get pods -n robot-shop

# Step 8: Apply Ingress
cat ingress.yaml
kubectl apply -f ingress.yaml
kubectl get ingress -n robot-shop
