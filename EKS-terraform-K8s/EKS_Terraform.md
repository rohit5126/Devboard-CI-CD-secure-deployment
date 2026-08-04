## EKS provision using terraform with K8s netwroking and load ablancer setup.

<img width="2720" height="2640" alt="eks_vpc_networking_2az (Copy)" src="https://github.com/user-attachments/assets/800b9ed6-4f26-4f1c-bbf3-f5cc40de4160" />


**Here's the plain-English breakdown of each piece in that setup:**

**The VPC** is just your own private network inside AWS — a big fenced-off address space (like 10.0.0.0/16) where everything else lives.

**2 Availability Zones (AZs)** are two physically separate data centers. You spread things across both so if one goes down, the other keeps running. 
This is why you need two of everything (two public subnets, two private subnets).

**Public subnets (one per AZ)** are the "outward facing" pieces of the network. They have a route to the internet. 
This is where things that need to be reachable from outside live — mainly your NAT gateways and the load balancer's network interfaces.

**Private subnets (one per AZ)** have no direct route in or out to the internet. 
This is where your actual worker nodes (EC2 instances running your pods) live — kept safely tucked away from direct internet exposure.

**Internet gateway (IGW)** is the door between your VPC and the internet. 
It's attached once to the VPC, and only the public subnets' route tables point to it (0.0.0.0/0 → IGW).

**NAT gateway** sits in each public subnet. Its job: let private-subnet nodes reach out to the internet (to pull container images, hit AWS APIs, download updates) without allowing anything to reach in. 
Each AZ gets its own NAT gateway so one AZ's private subnet doesn't depend on the other AZ — that's the whole point of "high availability."

**Route tables** are just the rulebook per subnet:

Public subnet route table → 0.0.0.0/0 goes to the Internet Gateway
Private subnet route table → 0.0.0.0/0 goes to that AZ's NAT Gateway

**Load balancer (ALB/NLB)** is the front door for traffic coming from users. It's deployed with a piece of itself in each public subnet 
(that's why it needs subnets in both AZs), and it forwards traffic down to your pods running in the private subnets. 
In EKS this is usually managed automatically by the **AWS Load Balancer** Controller, 
which watches your **Kubernetes Ingress or Service** objects and provisions/updates the actual ALB/NLB for you.

**EKS control plane** is the "brain" (API server, scheduler, etc.) — AWS runs and manages this for you; it just needs network access into your VPC (usually via ENIs placed in the private subnets).

**Worker nodes** are EC2 instances (grouped in a "managed node group" or self-managed Auto Scaling Group) that live in the private subnets and actually run your pods.

**Security groups** are the firewall rules at the instance/ENI level — one for the control plane, one for nodes, one for the load balancer — controlling exactly which traffic is allowed between them (e.g., ALB → node port, nodes → control plane API).

One extra detail specific to EKS: your subnets need specific tags so Kubernetes knows where it's allowed to place load balancers:

Public subnets: kubernetes.io/role/elb = 1
Private subnets: kubernetes.io/role/internal-elb = 1
All subnets: kubernetes.io/cluster/<cluster-name> = shared (or owned)

**Traffic flow in one line:** user → internet gateway → load balancer (public subnet) → worker node/pod (private subnet) → response goes back out the same path. 
Outbound traffic from pods (e.g., pulling an image) goes: private subnet → NAT gateway (public subnet) → internet gateway → internet.

-------------------------------------------------------------

Here's how a Node + Go + Postgres three-tier app would map onto that cluster, focusing purely on the networking side.

**The three tiers, mapped**

**Tier 1 – Presentation (Node.js):** likely your frontend / BFF (backend-for-frontend) service. Receives user traffic.
**Tier 2 – Application (Go):** your core business-logic API. Only talks to Node and to the database — never exposed directly to the internet.
**Tier 3 – Data (Postgres):** either RDS (recommended) or a self-hosted Postgres pod. Never exposed to the internet, ever.

**How traffic gets in**

User hits the ALB (sitting in the two public subnets, from the earlier setup).

ALB forwards to the **Node.js Service** — this is a Kubernetes Service of type ClusterIP, exposed externally only via an Ingress resource that the AWS Load Balancer Controller turns into ALB rules/target groups.
Node.js pods run on worker nodes in the private subnets. The ALB reaches into the **private subnet** over the VPC's internal routing — it does not need the pods to be publicly routable, just reachable within the VPC. 
This is the standard "internet-facing ALB, internal targets" pattern.

**How Node talks to Go**

Go is also a ClusterIP **Service — never** LoadBalancer or NodePort, since it should not be reachable from outside the cluster at all.
Node calls it via internal Kubernetes DNS: http://go-service.namespace.svc.cluster.local. kube-proxy/CoreDNS handles resolving that to the right pod IPs — no manual IP management needed, 
and it works the same regardless of which AZ either pod lands in.
This traffic never leaves the VPC — it's pod-to-pod over the cluster's internal networking (VPC CNI, so pods get real VPC IPs from the private subnet's CIDR range).

**How Go talks to Postgres**

This is where it matters most whether Postgres is in-cluster or RDS:

**Option A — RDS** (recommended for a real deployment):

RDS instance is deployed into the same private subnets (via a "DB subnet group" spanning both AZs) — not in the Kubernetes cluster at all.
Go connects using RDS's private endpoint (a DNS name resolving to a private IP inside your VPC).
A dedicated **RDS security group** allows inbound only on port 5432, and only from the node security group (or better, from the specific security group attached to the Go pods, if using security groups for pods). 
Nothing else can reach it — not Node, not the ALB, not the internet.
RDS Multi-AZ can give you a standby replica in the second AZ for failover.

**Option B — Self-hosted Postgres in the cluster**:

Runs as a StatefulSet with a ClusterIP (headless) Service, backed by an EBS-based PersistentVolume (EBS volumes are AZ-locked, so the pod becomes pinned to whichever AZ its volume lives in — a real limitation to know about).
Go reaches it the same way as Go-to-Go: internal DNS, ClusterIP, no external exposure.

**Namespaces and isolation**

Put each tier (or the whole app) in its own namespace — gives you a clean boundary for RBAC and network policy.
Use NetworkPolicies to enforce the tiers at the Kubernetes level too, not just via security groups:
Node's policy: allow ingress from the ALB/ingress-controller, allow egress to Go only.
Go's policy: allow ingress from Node only, allow egress to Postgres only.
Postgres: allow ingress from Go only, no egress needed.
This means even if something were misconfigured at the AWS security-group layer, the cluster itself still enforces "Node can't skip past Go to hit the DB directly."


**Secrets for DB credentials**

Store Postgres credentials in a Kubernetes Secret (or better, sync from **AWS Secrets Manager/Parameter** Store via the External Secrets Operator or CSI driver) — never bake them into the Go image or a ConfigMap.

Summary of the "never exposed" rule
The whole point of this layout: only the Ingress/ALB touches the public subnets and the internet. Everything else — Node pods, Go pods, 
Postgres — lives in the private subnets and talks to its neighbors only over internal cluster networking or internal AWS networking, 
restricted tier-by-tier by both security groups (AWS-level) and NetworkPolicies (Kubernetes-level).
![Uploading eks_vpc_networking_2az.png…]()


A few things worth calling out before you apply these:

Apply order matters: 00 → 01 → 02 → 03/04 (and 05 only if you're not using RDS) → 06 → 07. Ingress needs the LB Controller (from your Terraform Helm release) already running, or it'll sit there without provisioning an ALB.
NetworkPolicy enforcement: the default VPC CNI doesn't enforce NetworkPolicy objects out of the box on older EKS versions — you either need VPC CNI network policy support enabled (available on newer EKS/CNI versions) or a policy-enforcing CNI like Calico. Otherwise 06-network-policies.yaml applies cleanly but silently does nothing.
RDS vs in-cluster Postgres: only apply 05-postgres-statefulset.yaml if you chose the self-hosted route from the Terraform step. If using RDS, delete the postgres block from 06-network-policies.yaml and just rely on the RDS security group instead (a NetworkPolicy can't select a non-pod endpoint like RDS).
Placeholders to replace: <ECR_REPO>, <ACCOUNT_ID>, and the REPLACE_ME password — none of these will work as committed.
