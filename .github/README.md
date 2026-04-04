## Acessando o Cluster K8s e o ArgoCD

Ao terminar a execução bem-sucedida do Action Pipeline de Produção (que emitirá outputs formatados como Strings SSL do Redis e RDS já gerencialmente construídas no log), você já gerou um cluster com LoadBalancer para gerenciar suas deployments.

Siga os passos de acesso da máquina local:

**1. Interligar com seu Kubeconfig**
Garanta que seu terminal está logado na AWS e execute:

```bash
aws eks update-kubeconfig --name togglemaster-cluster --region us-east-1
```
Isso atrela seu `kubectl` ao cluster que acaba de ser originado.

**2. Descobrir a sua External URL do ArgoCD**
A porta de balanceamento foi declarada aberta na nossa recipe de infraestrutura, pergunte ao kubernetes qual foi a URL da AWS atribuída (ela muda a cada cluster recriado):

```bash
kubectl get svc argocd-server -n argocd -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
```
Copie esse endereço completo. Cole direto no navegador (`https://...`). Pule o bloqueio de segurança "Inseguro" se for gerado. Você verá a interface de UI do Argo.

**3. Pegar a Senha Inicial Automática do ArgoCD**
Para acessar usando o usuário base **`admin`**, você precisará do token secreto inicial instalado no EKS. Pegue ele formatado já em texto limpo com:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Faça o Login na UI com a senha criptografada e conecte os apps.
