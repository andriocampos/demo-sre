# 🔐 Autenticação GitHub Actions → AWS via OIDC

Este documento explica como construir a camada de autenticação **keyless** (sem
credenciais estáticas) usada por este projeto para que o GitHub Actions consiga
executar `terraform apply/destroy` na AWS.

> ⚠️ **Por que este código não está neste repositório?**
> Por questões de segurança e separação de responsabilidades, o Terraform que
> provisiona o **OIDC Provider** e a **IAM Role** foi movido para um repositório
> dedicado: **`aws-github-auth`**.
>
> Motivos:
> - **Blast radius reduzido:** a role de deploy é um recurso sensível (dá acesso
>   à conta AWS). Mantê-la isolada evita que mudanças no lab afetem a base de
>   autenticação.
> - **Least privilege / ciclo de vida distinto:** a infraestrutura de autenticação
>   é de longa duração (bootstrap), enquanto o lab é efêmero (apply/destroy).
> - **Controle de acesso separado:** permissões de quem edita a role ≠ de quem
>   edita o lab.
>
> Este guia permite que **qualquer pessoa que clone o repositório reproduza o
> cenário do zero**, mesmo sem acesso ao repositório `aws-github-auth`.

---

## 🎯 O que este componente cria

| Recurso | Função |
|---------|--------|
| **IAM OIDC Identity Provider** | Estabelece confiança entre a AWS e o emissor de tokens do GitHub (`token.actions.githubusercontent.com`) |
| **IAM Role** (`gha-sre-demo-deploy`) | Role que o workflow assume via `sts:AssumeRoleWithWebIdentity` |
| **IAM Policy** (inline ou gerenciada) | Permissões mínimas para o Terraform criar/destruir a infra do lab |

### Como o fluxo funciona

```
┌────────────────────┐        1. Solicita OIDC token          ┌──────────────────────────┐
│  GitHub Actions     │ ─────────────────────────────────────▶ │ token.actions.github...  │
│  (job com           │                                         │ (emissor OIDC)           │
│   id-token: write)  │ ◀───────────────────────────────────── │                          │
└─────────┬──────────┘        2. JWT assinado                   └──────────────────────────┘
          │
          │ 3. AssumeRoleWithWebIdentity (JWT + Role ARN)
          ▼
┌────────────────────┐        4. Valida JWT contra o           ┌──────────────────────────┐
│   AWS STS           │           OIDC Provider + trust policy  │  IAM OIDC Provider        │
│                     │ ─────────────────────────────────────▶ │  + IAM Role (trust)       │
└─────────┬──────────┘                                          └──────────────────────────┘
          │ 5. Credenciais temporárias (15min–1h)
          ▼
    terraform apply/destroy  →  VPC, EC2, S3 (state)
```

Nenhuma `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` é armazenada no GitHub.
O único segredo do repositório é o **ARN** da role (que não é sensível por si só).

---

## 🧱 Construção do código (repositório `aws-github-auth`)

Crie um repositório separado chamado `aws-github-auth` com os arquivos abaixo.

### `provider.tf`

```hcl
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### `variables.tf`

```hcl
variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "Owner (usuário ou organização) do GitHub"
  type        = string
  default     = "andriocampos"
}

variable "github_repo" {
  description = "Nome do repositório que poderá assumir a role"
  type        = string
  default     = "demo-sre"
}

variable "role_name" {
  description = "Nome da IAM Role de deploy"
  type        = string
  default     = "gha-sre-demo-deploy"
}
```

### `oidc.tf`

```hcl
# ---------------------------------------------------------------------------
# 1. OIDC Identity Provider — confiança entre AWS e GitHub Actions
# ---------------------------------------------------------------------------
# O thumbprint é validado automaticamente pela AWS desde 2023, mas o provider
# ainda exige o campo. Usa-se o data source TLS para obtê-lo dinamicamente.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# ---------------------------------------------------------------------------
# 2. Trust Policy — QUEM pode assumir a role
# ---------------------------------------------------------------------------
# Restringe a role ao repositório específico (least privilege no trust).
# 'sub' garante que apenas workflows daquele repo/branch obtenham credenciais.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Audience exigida pela action configure-aws-credentials
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restringe ao repositório (qualquer branch). Para travar em uma branch:
    #   "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    ManagedBy = "terraform"
    Purpose   = "github-actions-oidc-deploy"
  }
}

# ---------------------------------------------------------------------------
# 3. Permissões da role — o QUE o Terraform do lab precisa fazer
# ---------------------------------------------------------------------------
# LEAST PRIVILEGE: apenas as ações que o `terraform plan/apply/destroy` do
# módulo infra-demo realmente exerce.
#
# Recursos provisionados e ações correspondentes:
#   - aws_vpc / aws_subnet / aws_internet_gateway / aws_route_table(+assoc)
#   - aws_security_group (+ regras ingress/egress)
#   - aws_key_pair  (aws_instance usa a chave; tls_private_key é local, sem IAM)
#   - data.aws_ami  (DescribeImages)
#   - aws_instance  (+ volume EBS gp3, tags)
#
# Nota: as APIs de rede/criação do EC2 (RunInstances, Create*) NÃO suportam
# restrição confiável por ARN de recurso no momento da criação, por isso o
# bloco EC2 usa Resource "*". O escopo real é dado pela lista fechada de ações
# (nenhum "ec2:*") e pelo trust restrito ao repositório.
data "aws_iam_policy_document" "deploy_permissions" {

  # --- Leitura (describe) — necessária para plan/refresh/import ---
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeSubnets",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:DescribeVolumes",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }

  # --- VPC / Networking (create + delete + modify) ---
  statement {
    sid    = "EC2Networking"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable"
    ]
    resources = ["*"]
  }

  # --- Security Group + regras ---
  statement {
    sid    = "EC2SecurityGroup"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress"
    ]
    resources = ["*"]
  }

  # --- Key Pair (import da chave pública gerada pelo provider TLS) ---
  statement {
    sid    = "EC2KeyPair"
    effect = "Allow"
    actions = [
      "ec2:ImportKeyPair",
      "ec2:DeleteKeyPair"
    ]
    resources = ["*"]
  }

  # --- Instância EC2 + volume EBS ---
  statement {
    sid    = "EC2Instance"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances"
    ]
    resources = ["*"]
  }

  # --- Tags (Terraform adiciona tags em todos os recursos criados) ---
  statement {
    sid    = "EC2Tagging"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]
    resources = ["*"]
    # Restringe a criação de tags ao momento de criação dos recursos
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values = [
        "CreateVpc",
        "CreateSubnet",
        "CreateInternetGateway",
        "CreateRouteTable",
        "CreateSecurityGroup",
        "ImportKeyPair",
        "RunInstances"
      ]
    }
  }

  # --- Backend de state: restrito ao bucket do lab ---
  statement {
    sid    = "StateBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:ListBucketVersions"
    ]
    resources = [
      "arn:aws:s3:::tfstate-sre-demo-lab",
      "arn:aws:s3:::tfstate-sre-demo-lab/*"
    ]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_permissions.json
}
```

> **Sobre o `Resource: "*"` no bloco EC2:** as APIs de criação de rede/instância
> do EC2 não permitem restrição confiável por ARN no ato da criação. O
> least privilege aqui é obtido pela **lista fechada de ações** (sem `ec2:*`) e
> pelo **trust restrito ao repositório**. Para endurecer ainda mais, é possível
> adicionar `condition` por `aws:RequestedRegion` (travar em `us-east-1`) ou por
> tag (`aws:RequestTag/Environment = sre-demo`) nas ações de criação.

### `outputs.tf`

```hcl
output "role_arn" {
  description = "ARN da IAM Role — registre como secret AWS_ROLE_ARN no repositório do lab"
  value       = aws_iam_role.deploy.arn
}

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider criado"
  value       = aws_iam_openid_connect_provider.github.arn
}
```

---

## 🚀 Passo a passo para replicar

### 1. Provisionar a autenticação (uma única vez — bootstrap)

Como este código cria IAM (recurso sensível), o `apply` inicial é feito
**localmente**, com credenciais de administrador, e usa **state local** (não há
bootstrap de OIDC ainda).

```bash
# No repositório aws-github-auth
terraform init
terraform apply \
  -var="github_org=andriocampos" \
  -var="github_repo=demo-sre"

# Guarde o output:
terraform output role_arn
# ex.: arn:aws:iam::123456789012:role/gha-sre-demo-deploy
```

### 2. Registrar o ARN no repositório do lab

No repositório **`demo-sre`** (este), cadastre o ARN como **secret**:

```bash
gh secret set AWS_ROLE_ARN \
  --repo andriocampos/demo-sre \
  --body "arn:aws:iam::123456789012:role/gha-sre-demo-deploy"
```

Ou via UI: **Settings → Secrets and variables → Actions → New repository secret**
- Nome: `AWS_ROLE_ARN`
- Valor: o ARN retornado no passo 1

### 3. Confirmar o consumo no workflow

O `deploy-sre-demo.yml` já está configurado para usar OIDC:

```yaml
permissions:
  id-token: write          # obrigatório para OIDC
  contents: read

steps:
  - name: Autenticação AWS via OIDC
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: us-east-1
```

### 4. Validar

Rode o workflow com `action = apply`. O step de autenticação deve assumir a role
sem erros. Para um teste isolado, adicione temporariamente:

```yaml
  - run: aws sts get-caller-identity
```

O output deve mostrar o ARN da role assumida (`assumed-role/gha-sre-demo-deploy/...`).

---

## 🔒 Boas práticas de segurança aplicadas

| Prática | Como |
|---------|------|
| **Sem credenciais estáticas** | OIDC emite tokens de curta duração; nada de access keys no GitHub |
| **Trust restrito ao repo** | Condition `sub = repo:org/repo:*` impede outros repos de assumir a role |
| **Audience validada** | Condition `aud = sts.amazonaws.com` |
| **Permissões escopadas** | Ações EC2 enumeradas (sem `ec2:*`); S3 restrito ao bucket de state |
| **Separação de repositórios** | Autenticação (`aws-github-auth`) isolada do lab (`demo-sre`) |
| **Travar por branch (opcional)** | Ajuste o `sub` para `ref:refs/heads/main` para permitir só a `main` |

---

## 📎 Referências

- [Configuring OpenID Connect in AWS — GitHub Docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
