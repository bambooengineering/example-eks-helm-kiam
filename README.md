## A repo with scripts and templates to configure Kiam for an EKS cluster, deployed using CloudFormation and Helm.

To set up a CloudFormation created VPC with an EKS cluster and kiam installed and configured, 
perform the following:

```bash
# Clone the repository
git clone git@github.com:bambooengineering/example-eks-helm-kiam.git
cd example-eks-helm-kiam

# Set the region for your cluster and the existing AWS SSH key you wish to use
export AWS_DEFAULT_REGION="eu-west-1"
export KEY_NAME=some-key

# Run the script. It will take about 15 minutes.
./setup.sh
```

To tear it down, run:

```bash
./teardown.sh
```

Much more information and the full guide to using this repo can be found in the associated blog
post: https://bambooengineering.io/2019/06/14/kiam-on-eks-with-helm.html
