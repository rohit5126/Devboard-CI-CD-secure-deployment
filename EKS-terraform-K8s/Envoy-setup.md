## DevBoard on EKS

**Change Log — ALB Ingress → Envoy Gateway (Gateway API) Migration**

**Cluster: devboard  |  Region: eu-north-1  |  Namespace: devboard-app**

**1. Summary**

The AWS Load Balancer Controller and its supporting IAM policy/IRSA role were removed from the cluster and replaced with Envoy Gateway, using the Kubernetes Gateway API (Gateway + HTTPRoute) instead of the legacy Ingress resource. The NetworkPolicy allowing traffic into the frontend was updated to match the new traffic source. This document records exactly what was removed, what was added, and why.

**2. What Was Removed**

**2.1 — Terraform: Load Balancer Controller IAM/IRSA**

lb-controller-irsa.tf — the IRSA role and custom IAM policy resource that let the AWS Load Balancer Controller call AWS's ELB/EC2 APIs.
iam_policy.json — the AWS-published permission set that was attached to that IAM policy.
Why removed: the AWS Load Balancer Controller is no longer used to provision the cluster's ingress point, so the IAM permissions built specifically for it are no longer needed.

**2.2 — Kubernetes: the ALB Ingress object**

06-ingress.yaml — the Ingress resource (annotated with kubernetes.io/ingress.class: alb) that the Load Balancer Controller watched to provision an ALB.
Why removed: Ingress is being replaced by the Gateway API, which is the newer, implementation-agnostic standard for cluster traffic entry — no longer tied to a single vendor's controller (AWS's, in this case).

**3. What Was Added**

**3.1 — Envoy Gateway controller**

Installed via Helm into its own namespace, after first installing the upstream Gateway API CRDs (Gateway, HTTPRoute, GatewayClass, etc. are not built into Kubernetes by default and must be installed once per cluster).
```
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.1.2 -n envoy-gateway-system --create-namespace

#Envoy Gateway runs its own controller pod (envoy-gateway-system) that watches Gateway/HTTPRoute objects and manages the Envoy proxy data-plane pods that actually terminate and route traffic — the same conceptual role the AWS Load Balancer Controller played for ALB/Ingress, but implemented as proxy pods inside the cluster rather than an external AWS-managed ALB.

```

**3.2 — New file: 06-gateway.yaml (replaces 06-ingress.yaml)**

Three Gateway API resources, in the same file slot the old Ingress occupied:
GatewayClass "eg"        — declares Envoy Gateway as an available controllerGateway "devboard-gateway" — the actual listener (HTTP :80), replaces IngressHTTPRoute "devboard-route" — routes / to frontend-service:80, replaces Ingress rules
What each does:
GatewayClass — a cluster-wide, one-time declaration that Envoy Gateway is available as a Gateway implementation (controllerName: gateway.envoyproxy.io/gatewayclass-controller). Conceptually replaces the old kubernetes.io/ingress.class: alb annotation, but as a first-class object.
Gateway — the actual traffic entry point. Envoy Gateway watches this object and automatically provisions a backing Kubernetes Service (type LoadBalancer) plus Envoy proxy pods to serve it. This Service is what triggers AWS's built-in cloud-controller-manager to create a Classic ELB or NLB — no AWS Load Balancer Controller or custom IAM permissions required for this basic path.
HTTPRoute — defines the actual routing rule (path / → frontend-service:80), the same job the rules: block inside the old Ingress used to do.

**3.3 — New external endpoint**

Envoy Gateway auto-creates a Service of type LoadBalancer in envoy-gateway-system. Its external hostname is the new public entry point, replacing the old ALB hostname:
kubectl get svc -n envoy-gateway-systemkubectl get gateway -n devboard-appkubectl get httproute -n devboard-app
Verified working: the Gateway showed PROGRAMMED: True with a real ELB hostname (a83dc58273dca4a32acf6fa3d195350b-419136118.eu-north-1.elb.amazonaws.com), and the HTTPRoute was accepted.
Note: because this is a new hostname, the frontend's Vite preview.allowedHosts setting needed to already be (or be updated to) true / wildcarded — the previous fix scoped to the old ALB hostname would otherwise reproduce the same 403 Forbidden error seen earlier against the new hostname.

**4. NetworkPolicy Update**

07-network-policies.yaml's node-frontend-policy ingress rule previously allowed traffic from any namespace and any pod (empty namespaceSelector/podSelector), which was a broad rule originally needed because the ALB connected to pod IPs directly via its own ENI rather than as an identifiable in-cluster pod.
With Envoy Gateway, traffic now arrives from real, labeled proxy pods running in the envoy-gateway-system namespace, so the rule was tightened to match those pods specifically instead of leaving it wide open.
ingress:  - from:      - namespaceSelector:          matchLabels:            kubernetes.io/metadata.name: envoy-gateway-system        podSelector:          matchLabels:            gateway.envoyproxy.io/owning-gateway-namespace: devboard-app            gateway.envoyproxy.io/owning-gateway-name: devboard-gateway    ports:      - port: 4173
kubernetes.io/metadata.name is an automatic, built-in namespace label (Kubernetes 1.21+), so it reliably targets envoy-gateway-system without manually labeling the namespace.
All other rules in the file (default-deny-all, go-api-policy, postgres-policy) were left unchanged — the traffic paths they cover (frontend→backend, backend→postgres) did not change as part of this migration.

**4.1 — Issue hit while applying**

Symptom: kubectl apply rejected the file with: strict decoding error: unknown field "spec.ingress[0].namespaceSelector", unknown field "spec.ingress[0].podSelector".
Root cause: namespaceSelector and podSelector were indented as siblings of the "from:" key instead of being nested inside the single list item under "from: -". Kubernetes' from: field expects a list of peer objects, where each list item can contain both selectors together (combined with AND logic).
Fix: re-indented both selectors two spaces deeper, nesting them under the same "-" list item as a single peer entry, then re-applied successfully.

**5. File Change Summary**
File
Change
Status
lb-controller-irsa.tf
IRSA role + IAM policy for AWS Load Balancer Controller
Removed
iam_policy.json
AWS-published permission set for the controller
Removed
06-ingress.yaml
ALB Ingress object routing to frontend-service
Removed
06-gateway.yaml
GatewayClass + Gateway + HTTPRoute (Envoy Gateway)
Added (new)
07-network-policies.yaml
node-frontend-policy ingress rule scoped to envoy-gateway-system proxy pods instead of an open wildcard
Modified

**6. Verification**
```
kubectl get gateway -n devboard-app → PROGRAMMED: True, real ELB hostname assigned
kubectl get httproute -n devboard-app → route present and accepted
kubectl describe networkpolicy node-frontend-policy -n devboard-app → confirms updated selector
curl against the new ELB hostname → confirms end-to-end traffic flow through Envoy Gateway to the frontend
```

**7. Follow-ups**

Update the README/architecture diagram to reflect Envoy Gateway in place of the AWS Load Balancer Controller.
Confirm the frontend's Vite allowedHosts setting still covers the new ELB hostname (or remains wildcarded) so it isn't blocked again on any future hostname change.
Consider adding a TLS listener to the Gateway once a real domain/ACM-equivalent certificate is available — currently HTTP only, same as the previous ALB setup.

helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.5.9 -n envoy-gateway-system --create-namespace


