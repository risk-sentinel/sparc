# SPARC_HASH Rotation

How to rotate the `SPARC_HASH` master secret without losing access to the encrypted federation peer credentials it protects.

`SPARC_HASH` is the master secret that `SparcKeyDerivation` uses (HKDF-style via `ActiveSupport::KeyGenerator`) to derive purpose-specific keys for every encrypted column SPARC writes. Today the only consumers are `FederationPeer.encrypted_service_token` and `FederationPeer.encrypted_signing_secret`, but every future encrypted column will share the same master.

This document is for instance admins and ops engineers running SPARC on ECS Fargate. For the developer-focused architecture and NIST control mapping, see [`compliance/nist-sp800-53-rev5-mapping.md`](compliance/nist-sp800-53-rev5-mapping.md) (search "SPARC_HASH" / "Federation").

---

## TL;DR

```
1. Save the current SPARC_HASH value externally — you will need it as OLD_SPARC_HASH
2. Generate a new value, write it to AWS Secrets Manager `sparc-{env}/sparc-hash`
3. Force the running ECS service to pick up the new value (force-new-deployment)
4. Invoke a one-shot ECS task that runs `sparc:reencrypt:rotate_master_key` with OLD_SPARC_HASH set
5. Verify exit 0 + `sparc_hash_rotated` AuditEvent
```

Total ops time: under five minutes once the operator has the inputs ready. There is a brief window between steps 3 and 4 where federation peer outbound calls fail (the running task has the new master but peer credentials in the DB are still encrypted under the old one). The window is typically under 30 seconds end-to-end and is documented in [Step 4 below](#step-4--run-the-rotation-rake-as-a-one-shot-ecs-task).

---

## When to rotate

- **Scheduled** — annually or per your compliance baseline. SPARC has no automatic rotation for the master; this is an operator-driven event.
- **Reactive** — suspected compromise of `SPARC_HASH` (a leaked deployment env, a stolen secrets-manager version, an accidental log of the value).
- **Pre-federation** — before adding the first real (non-test) federation peer. Once a peer credential is encrypted under the current master, that master is load-bearing for that credential's confidentiality.

If `SPARC_HASH` is not set at all (the development default — falls back to `Rails.application.secret_key_base`), you do not need to rotate `SPARC_HASH` per se; rotate `secret_key_base` via the standard Rails credentials flow. The same rotation rake works either way as long as you supply the previous master value as `OLD_SPARC_HASH`.

---

## Architecture

```
              AWS Secrets Manager
            (sparc-{env}/sparc-hash)
                      │
                      │   ECS task definition
                      │   secrets injection
                      ▼
               ENV["SPARC_HASH"]
                      │
                      ▼
           SparcKeyDerivation.derive
        (per-purpose HKDF-style key derivation)
                      │
                      ▼
        AES-GCM encryption keys for:
          • FederationPeer.encrypted_service_token
          • FederationPeer.encrypted_signing_secret
```

**Source of truth:** AWS Secrets Manager `sparc-{env}/sparc-hash` AWSCURRENT.

**Trust boundary:** SPARC's task role does not have `GetSecretValue` for this secret in the application path; ECS reads it on SPARC's behalf and injects it as an env var at task start. This matches the `admin-credentials` model.

**What re-encryption does:** the rake task takes `OLD_SPARC_HASH` (the previous master value, supplied by the operator), iterates every `FederationPeer`, decrypts each encrypted column with a key derived from the old master, and re-saves it via the standard public setter — which re-encrypts under the *current* `SPARC_HASH` automatically. The work runs inside one DB transaction.

---

## Step-by-step rotation

### Step 1 — Save the current SPARC_HASH value externally

Read the current AWSCURRENT value of `sparc-{env}/sparc-hash` and **save it somewhere outside SPARC** (password manager, encrypted note, secure ops vault). You will hand it to the rotation rake as `OLD_SPARC_HASH`.

```bash
aws secretsmanager get-secret-value \
  --secret-id sparc-{env}/sparc-hash \
  --query SecretString --output text
# → the current SPARC_HASH value (raw string, not JSON)
```

If you skip this step you cannot complete the rotation — every encrypted federation peer credential in the DB will be unrecoverable. **Save it before continuing.**

### Step 2 — Write the new SPARC_HASH to Secrets Manager

Generate a new high-entropy value (≥48 bytes recommended; the rake refuses values shorter than 32) and write it as a new AWSCURRENT version:

```bash
NEW_HASH=$(openssl rand -hex 48)   # 96-character hex, ~48 bytes of entropy

aws secretsmanager put-secret-value \
  --secret-id sparc-{env}/sparc-hash \
  --secret-string "$NEW_HASH"
```

The new value is now AWSCURRENT but has not been picked up by the running ECS service yet — task definitions inject secrets at *task start*, not on demand.

### Step 3 — Force the running ECS service to pick up the new value

```bash
aws ecs update-service \
  --cluster sparc-{env} \
  --service sparc-{env}-app \
  --force-new-deployment
```

Watch the deployment until the new task is healthy:

```bash
aws ecs describe-services \
  --cluster sparc-{env} \
  --services sparc-{env}-app \
  --query 'services[0].deployments'
```

Once the rolling deployment is complete, the running app has the new `SPARC_HASH` in env. **At this point federation outbound calls will fail** — the app is trying to decrypt peer credentials with the new master, but the DB rows are still ciphertexts under the old master. Continue immediately to step 4.

### Step 4 — Run the rotation rake as a one-shot ECS task

ECS Exec is intentionally blocked in production, so the rake runs as an ephemeral ECS task that reuses the existing app task definition with `containerOverrides` for the command and the `OLD_SPARC_HASH` env var. **No IaC change is needed** — the same task definition serves the long-running web service and the one-shot rotation.

```bash
OLD_HASH="<the value you saved in step 1>"

aws ecs run-task \
  --cluster sparc-{env} \
  --task-definition sparc-{env}-app \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-ids>],securityGroups=[<sg-id>],assignPublicIp=DISABLED}" \
  --overrides '{
    "containerOverrides": [{
      "name": "app",
      "command": ["bundle", "exec", "rails", "sparc:reencrypt:rotate_master_key"],
      "environment": [
        {"name": "OLD_SPARC_HASH", "value": "'"$OLD_HASH"'"}
      ]
    }]
  }'
```

The container boots, runs the rake, writes the audit row, and exits. The new `SPARC_HASH` is already in env from the task definition's `secrets:` block — only `OLD_SPARC_HASH` needs to be supplied at run-task time.

**Watch the run:**

```bash
TASK_ARN=<the taskArn returned above>

aws ecs describe-tasks \
  --cluster sparc-{env} \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].{lastStatus:lastStatus,stopCode:stopCode,exitCode:containers[0].exitCode}'
```

Expect `lastStatus: STOPPED, stopCode: EssentialContainerExited, exitCode: 0`.

CloudWatch Logs (the same log group as the app service) will capture the rake's stdout. Look for:

```
============================================================
  SPARC_HASH Rotation Complete
============================================================
  Rotated:  3 peer(s)
  Skipped:  0 peer(s) (already on current key)
    - Acme Federation (id 1): service_token, signing_secret
    - Beta Federation (id 2): service_token, signing_secret
    - Gamma Federation (id 3): service_token
============================================================
```

### Step 5 — Verify

In the SPARC Rails console (or via the admin UI's audit log view):

```ruby
AuditEvent.where(action: "sparc_hash_rotated").order(:id).last
# → metadata: { peer_count_total: 3, rotated_count: 3, skipped_count: 0,
#               old_hash_fingerprint: "a1b2...", new_hash_fingerprint: "9f8e..." }
```

Verify federation outbound is healthy by triggering a peer call (push a federation bundle, or hit a peer health endpoint). Decryption of the now-current ciphertexts succeeds because they were re-encrypted under the new master in step 4.

---

## Idempotency and safe-to-retry behavior

The rake task is idempotent:

- Each peer's ciphertext is checked against the *current* encryptor first. If it decrypts, the row is already on the new master and is skipped.
- Only ciphertexts that fail under the current encryptor are decrypted with the old master and re-saved.
- Re-running the rake after a successful rotation produces `rotated: 0, skipped: <n>` — no DB writes, no new audit row implications.

If step 4 fails partway through (network blip, ECS task killed), the DB transaction rolls back and zero peers are mutated. Re-run the same `aws ecs run-task` invocation — it picks up exactly where it left off, which on a rollback is "from scratch."

---

## Drift recovery

If federation outbound calls keep failing after a rotation, you have drift between `ENV["SPARC_HASH"]` (what the running task uses) and the master that actually encrypts the DB rows.

### Symptom 1 — running task has the new master, DB rows are still under the old master

This is what step 3-without-step-4 looks like. Run step 4 with the saved `OLD_SPARC_HASH`. The rake auto-skips already-rotated rows so it is safe to run even if some peers were rotated previously.

### Symptom 2 — running task has the old master, DB rows are under the new master

You restored an earlier ECS task definition or rolled back a deployment after a successful rotation. Either:
- Re-deploy the app so it picks up the current `sparc-hash` AWSCURRENT, or
- If you genuinely need to roll back to the previous master, run the rake task again with `OLD_SPARC_HASH=<the new value>` after putting the old value back into AWSCURRENT — i.e., a rotation in reverse.

### Symptom 3 — neither master decrypts a specific peer

The rake aborts the entire transaction and surfaces the offending peer in its result:

```
[SparcHashRotation] FAILED: Peer "Acme Federation" field encrypted_service_token
decrypts under neither old nor current master: ActiveSupport::MessageEncryptor::InvalidMessage
(peer id: 42)
```

This means the row is corrupted (manual SQL edit, restore from a snapshot taken under a third master, etc.). No other peers were rotated — the transaction rolled back. Investigate that single peer (the audit log on its create/update events will show when it last had a known-good ciphertext) and either restore it from backup or zero out the encrypted columns and re-enroll the peer through the normal admin flow.

---

## Audit events

Each successful rotation produces one row in `audit_events`:

| `action` | When emitted | Notable metadata |
|---|---|---|
| `sparc_hash_rotated` | Rake task completed successfully (including no-op runs where every peer was already on the current key) | `peer_count_total: <n>`, `rotated_count: <n>`, `skipped_count: <n>`, `old_hash_fingerprint: <hex16>`, `new_hash_fingerprint: <hex16>` |

Fingerprints are the first 16 hex chars of `SHA-256(master)` — enough to confirm "we rotated from master A to master B" without ever exposing the raw value. They are deterministic, so two operators looking at separate audit rows can agree they were on the same master.

A no-op run (`rotated_count: 0, skipped_count: <total>`) still writes the audit row so that the audit log always reflects "an operator attempted a rotation at this time" regardless of whether work was needed.

**The plaintext SPARC_HASH (old or new) is never written to any audit row, log line, HTTP response, or notification.**

---

## Configuration reference

| Variable | Default | Set on | Purpose |
|---|---|---|---|
| `SPARC_HASH` | `Rails.application.secret_key_base` (fallback) | SPARC ECS secrets | Master secret. ECS-injected from `sparc-{env}/sparc-hash` AWSCURRENT. |
| `OLD_SPARC_HASH` | _(unset)_ | `aws ecs run-task` containerOverrides only | Previous master value, supplied to the rake at run-task time. **Never** committed to the task definition. |

`OLD_SPARC_HASH` is intentionally not part of the standing ECS task definition. It exists for the duration of the one-shot rotation task and is gone the moment the task exits. The operator's password manager / vault is the only durable home for the previous master between rotations.

---

## sparc-iac side requirements

**No IaC code changes are required for the rotation itself.** The rake reuses the existing app task definition.

The ops role / runbook executor needs IAM:
- `ecs:RunTask` on the `sparc-{env}-app` task definition
- `iam:PassRole` for the task execution role
- `ecs:DescribeTasks` to monitor the run
- `secretsmanager:PutSecretValue` on `sparc-{env}/sparc-hash` (to perform step 2)
- `secretsmanager:GetSecretValue` on `sparc-{env}/sparc-hash` (to perform step 1)

These are strictly less than what `ecs:ExecuteCommand` (ECS Exec) would require, so they should be cleaner to grant for a small ops group.

See [Rebel-Raiders/sparc-iac#200](https://github.com/Rebel-Raiders/sparc-iac/issues/200) for the release-coordination thread covering this rotation.

---

## FAQ

**Q: Do I have to take SPARC offline to rotate?**
A: No, but federation outbound calls will fail for the window between step 3 (force-new-deployment) and step 4 (rake exits). User-facing UI/API traffic that does not touch federation peer credentials is unaffected. The window is typically under 30 seconds — long enough to be visible in monitoring, short enough that the runbook does not require a maintenance window.

**Q: What happens if I lose the previous SPARC_HASH value?**
A: All `FederationPeer.encrypted_service_token` and `encrypted_signing_secret` rows become unrecoverable. There is no backdoor — the master secret is the only key. Mitigation: re-enroll every peer through the normal admin flow (each peer issues a fresh service token and signing secret). This is operationally annoying but recoverable.

**Q: Can I rotate `SPARC_HASH` without rotating the encrypted columns?**
A: No, not safely. The two are coupled by definition: the master derives the column encryption keys. Rotating the master without re-encrypting the columns leaves them encrypted under a value the running app no longer knows.

**Q: How often should I rotate?**
A: Annually is a reasonable starting point. Quarterly if your compliance baseline demands it. The work is idempotent and bounded; the binding constraint is the brief federation-outbound window in step 3-4.

**Q: Does this affect any other encrypted data?**
A: Today, no — `FederationPeer` is the only model with `SparcKeyDerivation`-derived keys. As future encrypted columns land, they will share the same master and rotate in the same step. The rake will need to be extended to iterate them; the runbook stays identical.

**Q: Why a fingerprint and not the version_id?**
A: Secrets Manager version IDs identify which SM version was current; fingerprints identify which *value* was current. If two SM versions happen to hold the same plaintext (e.g., a rollback), their version_ids differ but their fingerprints match — and the latter is what actually matters for "did the master change?"

**Q: Can the running web service do the rotation itself?**
A: It could (the service object is the same), but bundling it into a one-shot task keeps the long-running service free of the `OLD_SPARC_HASH` env, simplifies IAM (the rotation IAM does not have to live on the steady-state task role), and gives a clean audit boundary — one task, one rotation, one CloudWatch log group entry.

**Q: What if the rake fails partway through?**
A: The DB transaction rolls back; zero peers are mutated. Investigate the failure (CloudWatch logs of the failed task, plus the result struct's `error` and `error_peer_id` fields if a peer was the cause), fix the root cause, and re-run the same `run-task` invocation.

**Q: Can I test this without touching production?**
A: Yes. Stand up the rotation in staging (`sparc-staging/sparc-hash`) end-to-end, including the run-task pattern. The rake's spec coverage (`spec/services/federation_peer_reencryption_service_spec.rb`, `spec/lib/tasks/reencrypt_rake_spec.rb`) exercises the same code paths the production rake runs.

---

## Related documentation

- [`ADMIN_CREDENTIAL_ROTATION.md`](ADMIN_CREDENTIAL_ROTATION.md) — admin password rotation; the run-task pattern documented here is structurally similar to its rake-task path
- [`compliance/nist-sp800-53-rev5-mapping.md`](compliance/nist-sp800-53-rev5-mapping.md) — IA-5, SC-12, AU-2 mappings (search "SPARC_HASH" / "Federation")
- [Rebel-Raiders/sparc-iac#200](https://github.com/Rebel-Raiders/sparc-iac/issues/200) — release coordination thread
- SPARC issue [#419](https://github.com/Rebel-Raiders/sparc/issues/419) — the original feature request
