# 🚀 Lab Terraform — CI/CD, GitOps & AWS

Repositório de portfólio que demonstra práticas reais de **CI/CD**, **GitOps** e **Infrastructure as Code (IaC)** no ecossistema AWS. Cada módulo é um laboratório funcional que pode ser provisionado e destruído com um clique via GitHub Actions.

---

## 🎯 O que este repositório demonstra

| Competência | Implementação |
|---|---|
| **CI/CD** | Pipelines automatizadas com GitHub Actions (plan em PR, apply na main) |
| **GitOps** | Infraestrutura versionada no Git — toda mudança passa por workflow |
| **IaC** | Terraform modular (VPC, EC2, IAM, S3) com state management |
| **Configuração** | Ansible com roles idempotentes (Docker, Deploy, Validate) |
| **Segurança** | Autenticação sem credenciais estáticas via OIDC (keyless) |
| **Observabilidade** | Stack de monitoramento (Prometheus + Grafana) provisionada automaticamente |
| **FinOps** | Auto-destroy com TTL, bloqueio de execuções simultâneas e estimativa de custo/hora |

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
│                                                     │             │
│                                              ┌──────▼──────────┐  │
│                                              │ ⏱️ Auto-Destroy  │  │
│                                              │  (15min timer)  │  │
│                                              └──────┬──────────┘  │
│                                                     │             │
│                                              terraform destroy    │
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
│   ├── deploy-sre-demo.yml     # 🚀 Pipeline principal (apply/destroy one-click)
│   ├── lab-s3.yml              # Lab S3 com dispatch manual
│   ├── test-oidc.yml           # Teste de autenticação OIDC
│   └── desagio-labs3.yml       # Primeiro workflow didático
│
├── infra-demo/                  # Módulo principal — VPC + EC2 + Ansible
│   ├── versions.tf             # Terraform >= 1.5.7, backend S3 dinâmico
│   ├── provider.tf             # AWS provider (us-east-1)
│   ├── variables.tf            # Variáveis parametrizáveis
│   ├── vpc.tf                  # VPC + Subnet + IGW + Route Table
│   ├── ec2.tf                  # Security Group + Key Pair + EC2
│   ├── outputs.tf              # IP público, instance ID, chave SSH
│   └── ansible/                # Automação de configuração
│       ├── playbook.yml
│       └── roles/
│           ├── docker/         # Instalação Docker (Debian/RedHat)
│           ├── deploy/         # Build + Docker Compose (App + Monitoramento)
│           └── validate/       # Testa endpoints + rollback automático
│
├── aws-github-auth/             # OIDC Provider + IAM Role (GitHub → AWS)
│   └── oidc.tf
│
├── infra/                       # Módulo VPC avançado (multi-AZ, for_each)
│   ├── vpc.tf
│   └── variables.tf
│
├── desafios-lab/                # Labs isolados
│   └── lab-s3/                  # Bucket S3 com random suffix
│
└── docs/                        # Documentação técnica
    ├── ec2-iam-role-instance-profile.md
    └── guia-github-actions.md
```

---

## ⚡ Como usar

### Deploy completo (one-click)

1. Acesse **Actions** → **🚀 SRE Demo - Deploy/Destroy**
2. Clique **Run workflow** → selecione `apply`
3. Aguarde ~5 minutos
4. Acesse os links no **Job Summary**
5. ⏱️ Após **15 minutos**, a infra é destruída automaticamente

### Destruir manualmente (antes do TTL)

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

Este lab implementa duas travas automáticas para evitar gastos acidentais:

### ⏱️ Auto-Destroy (TTL: 15 minutos)

Após o deploy completo, um job de countdown é iniciado automaticamente:

```
apply → infra → ansible → summary → auto-destroy (15min timer)
                                          │
                                    ┌─────┴─────┐
                                    │  sleep 60  │ ← log a cada minuto
                                    │  × 15      │
                                    └─────┬─────┘
                                          │
                                          ▼
                                  terraform destroy
                                  + cleanup bucket S3
```

- O countdown exibe `Restam X minuto(s)...` no log a cada minuto
- Após 15 min, executa `terraform destroy -auto-approve` + remove bucket de state
- **TTL configurável** via variável `LAB_TTL_MINUTES` no workflow

### 🔒 Bloqueio de Execução Simultânea

Se você tentar um novo `apply` com a infra ainda ativa, o workflow **bloqueia** com mensagem:

```
╔══════════════════════════════════════════════════════╗
║           🚫  EXECUÇÃO BLOQUEADA                    ║
╠══════════════════════════════════════════════════════╣
║                                                      ║
║  O Lab já está em execução há 10 min.               ║
║  Faltam 5 min para o destroy automático.            ║
║                                                      ║
║  Opções:                                            ║
║    1. Aguarde o destroy automático                  ║
║    2. Execute manualmente com action = destroy      ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
```

**Como funciona:**
- Consulta instâncias EC2 com tag `Environment=sre-demo` em estado `running`
- Calcula tempo decorrido desde o `LaunchTime` da instância
- Compara com o TTL (15min) e exibe tempo restante
- Impede criação de infraestrutura duplicada

### Resumo das proteções

| Proteção | Gatilho | Ação |
|----------|---------|------|
| Auto-destroy | 15 min após deploy | Destrói tudo automaticamente |
| Bloqueio simultâneo | EC2 `sre-demo` ativa | Bloqueia apply + exibe tempo restante |
| State efêmero | Cada ciclo apply/destroy | Bucket S3 criado e removido junto |

---

## 🔐 Segurança

- **Zero credenciais estáticas** — Autenticação via OIDC (GitHub ↔ AWS)
- **Least privilege no scope** — Role assume restrita ao repositório específico
- **Chave SSH efêmera** — Gerada pelo Terraform a cada deploy, nunca persiste
- **State isolado** — Bucket S3 criado e destruído junto com a infra

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
| `lab-s3.yml` | Manual (apply/destroy) | Cria/destrói bucket S3 |
| `test-oidc.yml` | Manual | Valida autenticação OIDC com `sts get-caller-identity` |

---

## 🧠 Decisões técnicas

| Decisão | Justificativa |
|---------|---------------|
| Backend S3 efêmero | Lab descartável — state criado e destruído junto com a infra |
| Auto-destroy (TTL 15min) | Impede esquecimento — garante custo máximo de ~R$0.02 por execução |
| Bloqueio de concorrência | Evita infra duplicada e custos desnecessários |
| Tag-based detection | Usa tags EC2 para detectar lab ativo (sem dependência de state) |
| `t3.micro` | Suficiente para demo, custo mínimo ($0.012/hr) |
| Ansible via SSH (não SSM) | Demonstra configuração clássica + key management |
| Validação com rollback | Se algum serviço não responde, o Ansible desfaz o deploy |
| `terraform_wrapper: false` | Permite capturar outputs diretamente no workflow |
| `tls_private_key` no Terraform | Chave efêmera — não precisa de secrets management para lab |

---

## 📚 Documentação adicional

- [EC2 IAM Roles & Instance Profiles](docs/ec2-iam-role-instance-profile.md)
- [Guia GitHub Actions](docs/guia-github-actions.md)

---

## 👤 Autor

**Andrio Campos**
SRE | DevOps | AWS

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-blue?style=flat&logo=linkedin)](https://www.linkedin.com/in/andrio-campos-72316721/)
[![GitHub](https://img.shields.io/badge/GitHub-Follow-black?style=flat&logo=github)](https://github.com/andriocampos)
