# CLAUDE.md

Repository for managing pre-released tasks (Tasks 1 & 2) for the 2026 National Skills Competition Cloud Computing category using Terraform / eksctl / Kubernetes manifests. Around 10 sets are released prior to the competition, and the exam will be selected from these. Since each set uses a different combination of services, unify the directory structure across sets while filling in specific contents per set.

## Competition Structure

- AWS accounts are provided during the competition; personal accounts are not used. Each set is independent, so resource interference between sets (including grading items that scan the entire account) does not need to be considered.
- Only Tasks 1 & 2 are released in advance, from which the actual exam will be drawn.
- Task 1: A single task. Typically a comprehensive infrastructure in a single region.
- Task 2: Composed of multiple independent modules. The number of modules and regions vary per set.
- Refer to the README or task specifications of each set for specific service configurations.

## Environment

- OS: Windows 11
- Docker, AWS CLI, Terraform, and WSL are NOT installed.
- Files are reset upon reboot.
- School network environment.

## Directory Structure


```

skills-2026/
├── set-01/
│   ├── task-1/
│   │   ├── terraform/   # AWS resources
│   │   ├── eksctl/      # Cluster/nodegroup (EKS tasks only)
│   │   ├── k8s/         # k8s resources (numeric prefixes enforce apply order; group subdirectories allowed)
│   │   ├── app/         # Container source code (only when needed)
│   │   ├── task.md / task.pdf   # Task specifications
│   │   ├── mark.md / mark.pdf   # Grading criteria
│   │   └── mark.sh             # Grading script (single task → single file)
│   └── task-2/
│       ├── module-N-/   # Implementation: include only necessary terraform/ eksctl/ k8s/ app/ per module (descriptive names)
│       ├── provided/          # Competition-provided source files (DO NOT EDIT). Varies by set, separated by module (module1/, module2/, ...)
│       ├── mark/              # Grading scripts per module: mark2-1.sh, mark2-2.sh ... (mark<task#>-<module#>.sh)
│       ├── task.md / task.pdf · mark.md / mark.pdf
│       └── ...                # The number of modules varies per set
├── set-02/ ~ set-10/    # Same structure
├── shared/
│   ├── provided/         # Task distribution files
│   └── scripts/
└── .github/

```

Create subdirectories (`terraform/`, `eksctl/`, `k8s/`, `app/`) only as needed for each task. Not all tasks use EKS or containers.

## File Placement Rules

- `terraform/`: AWS resources. If there are many resources, separate files by domain.
- `eksctl/`: EKS cluster/nodegroup YAML files. Since this is an IaC layer like Terraform, place it at the same level as `terraform/`, not inside `k8s/`.
- `k8s/`: Resources to be applied via `kubectl apply` after cluster creation. Since application follows alphabetical order, force dependency order using numeric prefixes (`00-namespace.yaml`, `01-configmap.yaml`, etc.). If there are many domains, group them into subdirectories like `app/`, `monitoring/`, or `logging/`, and use numeric prefixes only on files with order dependencies.
- `app/`: Container source code to build and push to ECR.
- `provided/` (Task 2 only): Source files provided by the competition. Keep them unchanged in module subdirectories (`module1/`, `module2/`, ...). Write implementation code separately under `module-N-<name>/`.

## Design Rules

- **Design Sequence**: Map requirements ↔ resources using the task spec and grading sheet first, then stack them in dependency order — Network (VPC, Subnet, SG) → IAM → Data/Storage → Compute (EKS, EC2) → App/k8s → Observability. Break resources down into grading item units to prevent mapping breakage.
- **Preparing for 30% Changes**: Around 30% of the pre-released tasks may be modified or added on the day of the competition. Separate values into variables and repeated elements into modules, keeping clear resource boundaries so that partial requirement changes do not force a complete rewrite. Variables must be used for frequently changing axes like names, CIDRs, regions, instance types, and counts (aligned with Work Rule #5).

## Documentation Rules

Separate documentation for two readers with different timing:

- Root `README.md`: Index for all 10 sets + common workflow only. Do not include set-specific content.
- Set-specific `set-XX/task-Y/README.md`: **Quick Start (Runbook) only**. Pure execution commands from top to bottom, minimizing prose so work does not stall during the competition. Include a one-line overview, directory structure, and deployment steps.
- Design rationale, requirements ↔ implementation mappings, traps/caveats, and verification seeds ("why/verification" explanations) should be separated into a section at the bottom of the README. If it grows too large, move it to `ARCHITECTURE.md` in the same directory. (If separated, ensure the README runbook and architecture docs stay in sync.)
- Requirement ↔ implementation mapping tables directly relate to the grading sheet, so keep them in the explanation section (bottom of README or `ARCHITECTURE.md`).

## Terraform Variable Rules

- Set default values in `variables.tf`, and inject set-specific names, CIDRs, and regions via `terraform.tfvars`.
- Match resource names exactly with those specified in the task sheet (many grading items require exact name matches).

## State and Commands

- Terraform state is stored locally (`*.tfstate`) and excluded via `.gitignore`. Never commit tfstate files, `.terraform/` directories (provider binaries weighing hundreds of MBs), or `outputs.json`.
- Execute `apply` only on the local machine. Upload only `terraform output -json > outputs.json` to the bastion host and read values using `jq`.
- Follow the runbook in each `set-XX/task-Y/README.md` for detailed set commands (init/plan/apply, `eksctl create`, `kubectl apply`, grading script execution).

## Work Rules

1. Always check task.md, mark.md, and grading scripts (`mark.sh` for task-1, `mark/markN.sh` for task-2) before starting task work, troubleshooting, or finishing up.
2. Fix used software versions to the latest stable release at the time of writing (do NOT use `latest`). Exceptions:
   - Cluster management tools like `eksctl` and `helm` are not fixed; use the latest stable version.
   - Security-critical components like AL2023 allow `latest`.
   - Use specified versions (or `latest`) if explicitly required by task/grading specs.
   - EKS Addon versions are not fixed.
3. Verify modified manifests/terraform using relevant tools to ensure proper operation and fulfillment of grading criteria.
4. Grading is based on the exact structure checked by grading scripts. Even if fields appear redundant or unnecessary, do not remove grading target fields.
5. Declare values that easily change in competitions (names, CIDRs, regions, etc.) as variables to allow easy modification.
6. Prepare `.env` files on both local and bastion machines so bastion or CloudShell environment variables can be immediately restored upon reconnection.
7. `eksctl` and `helm` frequently change default values and schemas across versions (deprecated options, changed defaults). Check official documentation for current behavior before using options.
8. Manifest comments should only contain design rationale or relevant justification.

## Review

Intermittent checks performed during work. Runs even in an incomplete state.

- Run `terraform fmt`, `validate`, and `plan` to verify there are no unintended diffs.
- Cross-reference current implementations against grading script items and track missing items.
- Hardcoding check: Ensure easily changed values (names, CIDRs, regions, instance types) are extracted into variables.
- Security check: Ensure there are no excessive IAM permissions, `0.0.0.0/0` SGs, or plaintext secrets.
- Clean up unused/duplicate resources and ensure README runbook order matches actual deployment order.

## Completion Tasks

The review process performed once implementation for a task is complete (Work Rule #1 must precede).

1. Review whether a better implementation method exists.
2. Verify materials work using relevant tools and align with grading criteria.

## Commits / Branches

- Write commit messages in plain imperative mood without prefixes like `feat:` or `chore:`.
- Separate branches by set and task units.


## Language & Output Rules
- Always respond and communicate in Korean.

- User Documentation & Comments: All user-facing documents (README.md, ARCHITECTURE.md, etc.), task notes, and code/manifest comments MUST be written in Korean.

- Code & Technical Names: Keep resource names, variable names, and code syntax in English as required by the specifications.  

