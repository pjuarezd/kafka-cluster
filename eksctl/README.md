# Setup commands

Create the cluser with the config file

```sh
eksctl create cluster -f cluster.yaml
```

Install the EBS CSI Driver as a EKS add-on

```sh
eksctl create addon --name aws-ebs-csi-driver --cluster pedro-eks-cluster --force
```

Load Balancer controller, installed with helm
```sh
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=pedro-eks-cluster
```

Update kubeconfig context
```sh
aws eks update-kubeconfig --name pedro-eks-cluster
```

