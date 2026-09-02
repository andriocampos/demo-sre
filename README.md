# 🚀 Lab Terraform — CI/CD, GitOps & AWS

Repositório de portfólio que demonstra práticas reais de **CI/CD**, **GitOps** e **Infrastructure as Code (IaC)** no ecossistema AWS. Cada módulo é um laboratório funcional que pode ser provisionado e destruído com um clique via GitHub Actions.

---

## 🎯 O que este repositório demonstra

| Competência | Implementação |
|---|---|
| **CI/CD** | Pipelines automatizadas com GitHub Actions (plan em PR, apply na main) |
| **GitOps** | Infraestrutura versionada no Git — toda mudança passa por workflow |
| **IaC** | Terraform modular (VPC, EC2, Security Group, Key Pair) com backend S3 |
| **Configuração** | Ansible com roles idempotentes (Docker, Deploy, Validate) |
| **Segurança** | Autenticação sem credenciais estáticas via OIDC (keyless) |
| **Observabilidade** | Stack de monitoramento (Prometheus + Grafana) provisionada automaticamente |
| **FinOps** | Bloqueio de execuções simultâneas, state efêmero e estimativa de custo/hora |

---

## 📐 Arquitetura — Pipeline One-Click

```
┌──────────────────────────────────────────────────────────────────┐
│                        GitHub Actions                              │
│                                                                    │
│  ┌──────────┐   ┌─────────┐   ┌────────┐   ┌────────────────┐   │
│  │🔒 Check  │──▶│Terraform│──▶│Ansible │──▶│ Summary + Cost │   │
│  │Concurrent│   │ (Infra) │   │(Config)│   │  (Job Summary) │   │
│  └──────────┘   └─────────┘   └────────┘   └────────────────┘   │
│                                                                    │
│   🗑️  Destroy é MANUAL: Run workflow → action = destroy           │
└──────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                     AWS — us-east-1                                │
│                                                                    │
│   ┌────────────────── VPC 10.70.0.0/16 ──────────────────────┐   │
│   │                                                            │   │
│   │   Subnet Pública (10.70.1.0/24) ─── Internet Gateway      │   │
│   │   │                                                        │   │
│   │   └── EC2 (t3.micro)                                      │   │
│   │       ├── Nginx (Reverse Proxy :80)                        │   │
│   │       ├── Go API (/api-info)                               │   │
│   │       ├── Prometheus (/prometheus)                         │   │
│   │       └── Grafana (/grafana)                               │   │
│   │                                                            │   │
│   └────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📁 Estrutura do Repositório

```
.
├── .github/workflows/
│   └── deploy-sre-demo.yml     # 🚀 Pipeline principal (apply/destroy one-click)
│
└── infra-demo/                  # Módulo principal — VPC + EC2 + Ansible
    ├── versions.tf             # Terraform >= 1.5.7, backend S3 dinâmico
    ├── provider.tf             # AWS provider (us-east-1)
    ├── variables.tf            # Variáveis parametrizáveis
    ├── vpc.tf                  # VPC + Subnet + IGW + Route Table
    ├── ec2.tf                  # Security Group + Key Pair + EC2
    ├── outputs.tf              # IP público, instance ID, chave SSH
    └── ansible/                # Automação de configuração
        ├── playbook.yml
        ├── ansible.cfg
        └── roles/
            ├── docker/         # Instalação Docker (Debian/RedHat)
            ├── deploy/         # Build + Docker Compose (App + Monitoramento)
            └── validate/       # Testa endpoints + rollback automático
```

---

## ⚡ Como usar

### Deploy completo (one-click)

> **Pré-requisito:** o secret `AWS_ROLE_ARN` deve estar configurado no repositório.
> Ele aponta para a IAM Role criada no repo `aws-github-auth`. Consulte
> **[docs/oidc.md](docs/oidc.md)** para provisionar e registrar o secret.

1. Acesse **Actions** → **🚀 SRE Demo - Deploy/Destroy**
2. Clique **Run workflow** → selecione `apply`
3. Aguarde ~5 minutos
4. Acesse os links no **Job Summary**

> ⚠️ **Não há auto-destroy.** A infraestrutura permanece ativa (gerando custo) até você destruí-la manualmente.

### Destruir (obrigatório ao terminar)

1. Mesmo workflow → selecione `destroy`
2. Remove **toda** a infraestrutura + bucket de state

### Resultado esperado

Ao final do apply, o Job Summary exibe:

| Serviço | URL |
|---------|-----|
| Aplicação | `http://<IP>/api-info` |
| Grafana | `http://<IP>/grafana/` (admin/admin) |
| Prometheus | `http://<IP>/prometheus/` |

E a estimativa de custo:

| Recurso | Custo/hora |
|---------|-----------|
| EC2 t3.micro | $0.0104 |
| EBS 20GB gp3 | $0.0022 |
| **TOTAL** | **$0.0126/hr (~R$ 0.07/hr)** |

---

## 💰 Segurança de Custo (FinOps)

> ⚠️ **Atenção:** este lab **não possui destruição automática**. Ao terminar de usar,
> execute o workflow com `action = destroy` para não gerar custo contínuo.
> Recomenda-se configurar um **AWS Budgets** para alertas de gasto.

### 🔒 Bloqueio de Execução Simultânea

Se você tentar um novo `apply` com a infra ainda ativa, o workflow **bloqueia** com mensagem:

```
╔══════════════════════════════════════════════════════╗
║           🚫  EXECUÇÃO BLOQUEADA                    ║
╠══════════════════════════════════════════════════════╣
║                                                      ║
║  O Lab já está em execução há ~10 min.              ║
║  ⚠️  NÃO há destroy automático — destrua manualmente.║
║                                                      ║
║  Opções:                                            ║
║    1. Use o lab existente                           ║
║    2. Execute manualmente com action = destroy      ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
```

**Como funciona:**
- Verifica se o **bucket de state S3** (`tfstate-sre-demo-lab`) já existe
- Se existir, o lab está ativo → calcula há quanto tempo pelo `LastModified` do state
- Impede a criação de infraestrutura duplicada (`exit 1`)

### Resumo das proteções

| Proteção | Gatilho | Ação |
|----------|---------|------|
| Bloqueio simultâneo | Bucket de state S3 existente | Bloqueia apply + exibe tempo ativo |
| State efêmero | Cada ciclo apply/destroy | Bucket S3 criado e removido junto |
| Estimativa de custo | Ao final do apply | Exibe custo/hora no Job Summary |

---

## 🔐 Segurança

- **Zero credenciais estáticas** — Autenticação via OIDC (GitHub ↔ AWS)
- **Least privilege no scope** — Role assume restrita ao repositório específico
- **Chave SSH efêmera** — Gerada pelo Terraform a cada deploy, nunca persiste
- **State isolado** — Bucket S3 criado e destruído junto com a infra

### 🔑 Autenticação isolada — repositório `aws-github-auth`

Por questões de segurança, o Terraform que provisiona o **OIDC Provider** e a
**IAM Role** de deploy **não vive neste repositório**. Ele foi separado no
repositório dedicado **`aws-github-auth`**, reduzindo o blast radius: a base de
autenticação (recurso sensível e de longa duração) fica isolada do lab efêmero.

Este repositório apenas **consome** a role via o secret `AWS_ROLE_ARN`.

> 📖 Quer replicar o cenário do zero? Veja **[docs/oidc.md](docs/oidc.md)** — guia
> completo para reconstruir o OIDC Provider + IAM Role e registrar o secret.

---

## 🛠️ Tecnologias

| Categoria | Ferramenta |
|-----------|-----------|
| IaC | Terraform 1.5.7 |
| Config Management | Ansible |
| CI/CD | GitHub Actions |
| Cloud | AWS (VPC, EC2, IAM, S3) |
| Containers | Docker + Docker Compose |
| Aplicação | Go (HTTP server com métricas) |
| Monitoramento | Prometheus + Grafana |
| Reverse Proxy | Nginx |
| Autenticação | OpenID Connect (OIDC) |

---

## 📊 Workflows disponíveis

| Workflow | Trigger | Descrição |
|----------|---------|-----------|
| `deploy-sre-demo.yml` | Manual (apply/destroy) | Pipeline completa: Infra + Config + Validação |

---

## 🧠 Decisões técnicas

| Decisão | Justificativa |
|---------|---------------|
| Backend S3 efêmero | Lab descartável — state criado e destruído junto com a infra |
| Destroy manual | Controle explícito do ciclo de vida — sem timers automáticos |
| Bloqueio de concorrência | Evita infra duplicada e custos desnecessários |
| Lock via bucket de state | Presença do bucket S3 sinaliza lab ativo (sem dependência de tags) |
| `t3.micro` | Suficiente para demo, custo mínimo ($0.012/hr) |
| Ansible via SSH (não SSM) | Demonstra configuração clássica + key management |
| Validação com rollback | Se algum serviço não responde, o Ansible desfaz o deploy |
| `terraform_wrapper: false` | Permite capturar outputs diretamente no workflow |
| `tls_private_key` no Terraform | Chave efêmera — não precisa de secrets management para lab |

---

## 📚 Documentação adicional

- [Autenticação OIDC (GitHub → AWS) e repo `aws-github-auth`](docs/oidc.md)

---

## 👤 Autor

**Andrio Campos**
SRE | DevOps | AWS

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-blue?style=flat&logo=linkedin)](https://www.linkedin.com/in/andrio-campos-72316721/)
[![GitHub](https://img.shields.io/badge/GitHub-Follow-black?style=flat&logo=github)](https://github.com/andriocampos)
