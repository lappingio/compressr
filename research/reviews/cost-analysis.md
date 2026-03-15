# Compressr AWS Cost Analysis: Infrastructure, TCO, and Optimization

## 1. Infrastructure Cost Modeling

### Assumptions & Sizing Baseline

Cribl's documented sizing is **~200 GB/day per vCPU (x86)** and **~480 GB/day per vCPU (Graviton/ARM)**. The BEAM VM is not Node.js (Cribl's runtime), so throughput per vCPU will differ. I will model compressr conservatively at **150 GB/day per vCPU on Graviton** initially (BEAM is excellent at concurrency but unproven at this specific workload), with a stretch target of matching Cribl's 480 GB/day per vCPU after optimization.

All prices are **us-east-1, on-demand, as of early 2025**. Reserved/Savings Plan pricing discussed in Section 8.

### 1 TB/day (Single Node — The SMB Sweet Spot)

| Component | Spec | Monthly Cost |
|---|---|---|
| **EC2 (Graviton)** | c7g.xlarge (4 vCPU, 8 GB RAM) | $88 |
| **EBS gp3** | 200 GB buffer (covers ~4.8 hr outage) | $16 |
| **DynamoDB** | Free tier (25 RCU/WCU, 25 GB) | $0 |
| **S3 archive destination** | ~30 TB/mo stored (assuming 1 month retention, gzip ~3:1 compression = 10 TB stored) | $230 (S3 Standard) |
| **S3 PUTs** | ~10M PUTs/mo (100 MB files) | $50 |
| **Data transfer out** | Minimal (data stays in-region to S3/ES) | ~$5 |
| **Cross-AZ transfer** | None (single node) | $0 |
| **CloudWatch** | Basic monitoring + custom metrics | $10 |
| **Total** | | **~$399/mo** |

Notes: S3 cost dominates. If archiving to Glacier Flexible Retrieval instead of Standard, stored data drops to $36/mo (10 TB x $0.0036/GB). That brings total to **~$205/mo**.

### 5 TB/day (Growing SMB)

| Component | Spec | Monthly Cost |
|---|---|---|
| **EC2 (Graviton)** | 2x c7g.2xlarge (8 vCPU, 16 GB each) | $470 |
| **EBS gp3** | 2x 500 GB buffer (~2.4 hr outage per node) | $80 |
| **DynamoDB** | Still free tier (config only) | $0 |
| **S3 archive** | 50 TB stored (compressed, 1 mo retention) | $1,150 (Standard) / $180 (Glacier Flex) |
| **S3 PUTs** | ~50M PUTs/mo | $250 |
| **Data transfer** | Cross-AZ between 2 nodes: ~5 TB/mo at $0.01/GB each way | $100 |
| **CloudWatch** | | $15 |
| **Total (S3 Standard)** | | **~$2,065/mo** |
| **Total (Glacier Flex)** | | **~$1,095/mo** |

### 10 TB/day (Upper SMB / Lower Mid-Market)

| Component | Spec | Monthly Cost |
|---|---|---|
| **EC2 (Graviton)** | 3x c7g.4xlarge (16 vCPU, 32 GB each) | $1,410 |
| **EBS gp3** | 3x 1 TB buffer | $240 |
| **DynamoDB** | Likely still free tier, borderline | $0–$10 |
| **S3 archive** | 100 TB stored (compressed, 1 mo) | $2,300 (Standard) / $360 (Glacier Flex) |
| **S3 PUTs** | ~100M PUTs/mo | $500 |
| **Data transfer** | Cross-AZ: ~10 TB/mo routed between nodes | $200 |
| **CloudWatch** | | $20 |
| **Total (S3 Standard)** | | **~$4,670/mo** |
| **Total (Glacier Flex)** | | **~$2,730/mo** |

### 50 TB/day (Stretch Target)

| Component | Spec | Monthly Cost |
|---|---|---|
| **EC2 (Graviton)** | 10x c7g.4xlarge or 5x c7g.8xlarge | $4,700–$5,600 |
| **EBS gp3** | 10x 2 TB buffer or NVMe instance store | $1,600 (EBS) / $0 (instance store) |
| **DynamoDB** | Free tier for config; collection state needs provisioned | $25–$50 |
| **S3 archive** | 500 TB stored (compressed, 1 mo) | $11,500 (Standard) / $1,800 (Glacier Flex) |
| **S3 PUTs** | ~500M PUTs/mo | $2,500 |
| **Data transfer** | Cross-AZ: ~50 TB/mo | $1,000 |
| **CloudWatch** | | $50 |
| **Total (S3 Standard)** | | **~$21,350/mo** |
| **Total (Glacier Flex)** | | **~$11,650/mo** |

---

## 2. Comparison to Cribl Stream

Cribl's pricing is not publicly listed but follows a **per-TB/day licensed model**. Based on industry data:

| Volume | Cribl Stream (estimated annual) | Compressr (annual, Glacier Flex archive) | Savings |
|---|---|---|---|
| 1 TB/day | $36K–$60K | $2,460 | **93–96%** |
| 5 TB/day | $120K–$180K | $13,140 | **89–93%** |
| 10 TB/day | $200K–$360K | $32,760 | **84–91%** |
| 50 TB/day | $500K–$1M+ | $139,800 | **72–86%** |

**Critical caveat**: These Cribl estimates include their support, managed updates, and a battle-tested product. Compressr's cost advantage is entirely infrastructure — the operational cost (Section 7) narrows the gap significantly.

At 1 TB/day, the comparison is devastating for Cribl. An SMB paying $3K–$5K/month for Cribl licensing could run compressr for $200/month in infrastructure. Even adding one engineer's partial time (Section 7), the economics are overwhelming.

---

## 3. DynamoDB Cost Analysis

### What Goes Into DynamoDB
- Source configurations (tens of items)
- Destination configurations (tens of items)
- Pipeline configurations (tens to hundreds)
- Route configurations (tens)
- S3 collection state (one item per collected object — **this is the landmine**)
- Glacier restore tracking (temporary items)
- Node/cluster membership metadata

### Free Tier Math

DynamoDB free tier: **25 WCU, 25 RCU, 25 GB storage**. One WCU = 1 write/second of items up to 1 KB. One RCU = 1 strongly consistent read/second of items up to 4 KB.

**Config operations**: Even with 100 sources, 100 destinations, 50 pipelines — that is ~250 items. Config reads/writes are bursty (on deploy, on node boot) but average well under 1 WCU sustained. **Free tier is fine** for config.

**S3 collection state is the problem**: At 1 TB/day with 100 MB files, that is ~10,000 new objects/day. Each needs a write (track as collected) and a read (check before re-processing). That is ~0.12 WCU and ~0.12 RCU sustained — still fine.

At 50 TB/day with smaller files (10 MB each), that is 5,000,000 objects/day = ~58 WCU sustained. **This blows past free tier.** At on-demand pricing ($1.25/million writes), that is ~$6.25/day or **~$190/month**. Not huge, but no longer free.

**Recommendation**: Use DynamoDB TTL to expire collection state records after the collection window closes. Keep the table lean. At scale, switch from on-demand to provisioned capacity with auto-scaling.

### Verdict
Config storage stays in free tier at all volumes. S3 collection state tracking exits free tier somewhere between 10–50 TB/day depending on object size. Budget $0 at 1 TB/day, $0–$10 at 10 TB/day, $50–$200 at 50 TB/day.

---

## 4. Data Transfer Costs — The Hidden Killer

### Cross-AZ Traffic (Node-to-Node)

Compressr's architecture routes events from source nodes to destination-owning nodes via the consistent hash ring. If nodes are in different AZs (which they should be for HA), every routed event incurs **$0.01/GB in each direction** ($0.02/GB round trip including ACK overhead).

**The key question**: What fraction of events need to cross node boundaries?

With a consistent hash ring where each destination is owned by one node, and sources can land on any node, roughly **(N-1)/N** of traffic for a given destination crosses the network (where N = node count). For 3 nodes, that is ~67% of all traffic.

| Volume | Cross-AZ Data | Monthly Cost |
|---|---|---|
| 1 TB/day (1 node) | 0 | $0 |
| 5 TB/day (2 nodes) | ~2.5 TB/day = 75 TB/mo | $750 |
| 10 TB/day (3 nodes) | ~6.7 TB/day = 200 TB/mo | $2,000 |
| 50 TB/day (10 nodes) | ~45 TB/day = 1,350 TB/mo | $13,500 |

**This is a problem.** At 50 TB/day, cross-AZ transfer alone is $13,500/month — more than all compute costs combined.

### Mitigation Strategies

1. **AZ-affinity routing**: Route events to a destination owner in the same AZ when possible. This requires AZ-aware hash ring placement. Reduces cross-AZ by 60–70%.
2. **Process-at-source, forward post-pipeline**: The architecture already does this (good — pipeline processing reduces volume before forwarding). If pipelines achieve 50% volume reduction, cross-AZ cost halves.
3. **Single-AZ deployment**: Many SMBs will accept the availability tradeoff for massive cost savings. A 3-node cluster in one AZ costs $0 in cross-AZ transfer. Document this as the default for cost-sensitive deployments.
4. **Placement groups**: Put all nodes in one AZ with a spread placement group. Still get hardware diversity without cross-AZ costs.

### S3 PUT/GET Costs

- S3 PUT: $0.005 per 1,000 requests
- S3 GET: $0.0004 per 1,000 requests
- S3 data transfer in (upload): Free
- S3 data transfer out (download, same region): Free
- S3 data transfer out (cross-region or internet): $0.09/GB

For archive destinations, PUT costs are the main concern. At 100 MB file sizes:

| Volume | PUTs/month | Cost |
|---|---|---|
| 1 TB/day | 300K | $1.50 |
| 10 TB/day | 3M | $15 |
| 50 TB/day | 15M | $75 |

**Not a major cost driver** at reasonable file sizes. However, if file close conditions are too aggressive (small files), this can 10x. A flush-every-10-seconds policy with low volume creates many tiny files. **Set minimum file sizes of 50–100 MB.**

### Glacier Restore Costs (Replay Feature)

This is the killer feature's hidden cost:

| Tier | Per-request | Per-GB retrieved | 1 TB restore cost |
|---|---|---|---|
| Instant Retrieval | $0.01/1K | $0.03/GB | ~$30 |
| Flexible Retrieval (Standard, 3-5 hr) | $0.05/1K | $0.01/GB | ~$10 |
| Flexible Retrieval (Bulk, 5-12 hr) | $0.025/1K | $0.0025/GB | ~$2.50 |
| Deep Archive (Standard, 12 hr) | $0.10/1K | $0.02/GB | ~$20 |
| Deep Archive (Bulk, 48 hr) | $0.025/1K | $0.0025/GB | ~$2.50 |

**Recommendation**: Default to Bulk retrieval tier. The latency is fine for replay use cases (nobody needs 48-hour-old logs in 3 hours). Expose a "priority replay" option at higher cost. Show estimated restore cost in the UI before the user confirms — this prevents bill shock, which is a massive trust issue for SMBs.

---

## 5. Buffer Storage Costs

### EBS gp3 vs. Instance Store NVMe

| | EBS gp3 | Instance Store NVMe |
|---|---|---|
| **Cost (1 TB)** | $80/mo | $0 (included in instance price) |
| **IOPS** | 3,000 baseline, up to 16,000 | 100K–400K+ |
| **Throughput** | 125 MB/s baseline, up to 1,000 MB/s | 1–4 GB/s |
| **Durability** | 99.8–99.9% annual (data persists on stop) | **Ephemeral — lost on stop/terminate** |
| **Right choice** | 1–10 TB/day, need buffer persistence | 50 TB/day, need raw throughput |

### Analysis by Scale Point

**1 TB/day**: EBS gp3, no question. 200 GB at $16/mo. Buffer persistence matters for a single-node deployment — if the node reboots, you do not want to lose your buffer.

**5 TB/day**: EBS gp3 still wins. 500 GB per node at $40/mo each. The throughput requirement is ~60 MB/s sustained (5 TB / 86,400 seconds), well within gp3 baseline.

**10 TB/day**: EBS gp3 still fine. 1 TB per node at $80/mo. Throughput is ~115 MB/s sustained — need to bump gp3 throughput to 250 MB/s ($4/mo extra). Still cheap.

**50 TB/day**: Consider i4i or i3en instances with NVMe instance store. i4i.2xlarge has 8 vCPU + 1x 1.25 TB NVMe at $0.598/hr ($430/mo). Compare to c7g.2xlarge ($235/mo) + 1 TB EBS gp3 ($80/mo) = $315/mo. The i4i is $115/mo more, but you get 4x the I/O throughput and no EBS network bandwidth consumption. **At 50 TB/day, the I/O throughput justifies instance store.**

**Key risk with instance store**: The buffer is ephemeral. If a node dies, buffered events are lost. The architecture accepts this as a double-fault scenario (destination down AND node dies). For SMBs, this is the right tradeoff. For the "zero-loss" use case, the shadow-archive-to-S3 feature (mentioned as future in the project spec) is the answer.

**Recommendation**: Default to EBS gp3 for all deployments up to 10 TB/day. Document instance store as an advanced option for 50 TB/day with explicit warnings about data loss risk.

---

## 6. Graviton vs. x86 for the BEAM

### Pricing Differential

Graviton instances are **~20% cheaper** than equivalent x86 instances:

| Instance | vCPU | RAM | On-Demand $/hr | Monthly |
|---|---|---|---|---|
| c7g.xlarge (Graviton) | 4 | 8 GB | $0.1207 | $88 |
| c7a.xlarge (AMD x86) | 4 | 8 GB | $0.1531 | $112 |
| c7i.xlarge (Intel x86) | 4 | 8 GB | $0.1491 | $109 |

### BEAM Performance on ARM

The Erlang BEAM VM runs well on ARM64. Key considerations:

1. **JIT compiler**: The BEAM JIT (introduced in OTP 24) supports ARM64 natively. Performance is on par with or better than x86 for most workloads.
2. **No hyperthreading on Graviton**: Each vCPU is a full physical core. The BEAM scheduler works best with real cores, not hyperthreads. Cribl's own docs recommend -1 worker offset on ARM for this reason — because every core delivers full throughput.
3. **Memory bandwidth**: Graviton3 has excellent memory bandwidth, which helps the BEAM's garbage collection (per-process GC in the BEAM means lots of small allocations and deallocations).
4. **NIF compatibility**: If you go the RocksDB route (Rox NIF), ensure it compiles cleanly on aarch64. It does, but this is a CI concern.

### Cribl's Own Numbers

Cribl reports **480 GB/day per vCPU on Graviton vs. 200 GB/day on x86** — a **2.4x throughput improvement**. If even half of this translates to the BEAM (conservatively, 1.5x), Graviton is the clear winner: 20% cheaper AND 50%+ more throughput per core.

**Recommendation**: Graviton-first, always. Build ARM64 container images as the primary artifact. Provide x86 images for compatibility but do not optimize for them. This is a no-brainer — better performance at lower cost.

---

## 7. Operational Cost (TCO Including People)

This is where the CFO conversation gets real. Infrastructure is cheap. People are not.

### Staffing Model by Scale

| Volume | Required Expertise | FTE Allocation | Annual People Cost |
|---|---|---|---|
| 1 TB/day | Part-time SRE/DevOps | 0.1 FTE | $15K–$20K |
| 5 TB/day | Part-time SRE + on-call | 0.25 FTE | $37K–$50K |
| 10 TB/day | Dedicated SRE + backup | 0.5 FTE | $75K–$100K |
| 50 TB/day | SRE team (2 people) | 1.5 FTE | $225K–$300K |

Assuming fully-loaded SRE cost of $150K–$200K/year.

### What Operational Tasks Exist

1. **Upgrades**: BEAM hot code loading is a superpower here, but compressr is not Erlang/OTP telecom software — realistically, upgrades mean container deployments. Budget 2–4 hours/month for upgrade testing and rollout.
2. **Monitoring & alerting**: Who watches the watcher? Need external monitoring of compressr itself. Budget 2 hours/month for alert tuning and response.
3. **Capacity planning**: At growth rates, when do you add nodes? Budget 2 hours/month.
4. **Incident response**: Pipeline down at 2 AM means logs are not flowing to your SIEM. This requires on-call. At 1 TB/day, maybe you accept risk. At 10 TB/day, you need 24/7 coverage.
5. **Configuration management**: Pipeline changes, new sources/destinations. This is user work, not operational, but someone needs to know the tool.
6. **Security patches**: Elixir/OTP, container base image, NIF dependencies. Budget 4 hours/month.
7. **DynamoDB and AWS maintenance**: Minimal, but IAM policies, VPC config, security groups need upkeep.

### Full TCO Comparison

| Volume | Compressr Infra (annual) | Compressr Ops (annual) | Compressr TCO | Cribl License (annual) | Cribl Ops (annual) | Cribl TCO |
|---|---|---|---|---|---|---|
| 1 TB/day | $2,460 | $17,500 | **$20K** | $48K | $10K | **$58K** |
| 5 TB/day | $13,140 | $43,500 | **$57K** | $150K | $20K | **$170K** |
| 10 TB/day | $32,760 | $87,500 | **$120K** | $280K | $30K | **$310K** |
| 50 TB/day | $139,800 | $262,500 | **$402K** | $750K | $50K | **$800K** |

Cribl's operational cost is lower because they handle upgrades, support, and have deep expertise built into their product. But even with TCO including people, compressr is **50–65% cheaper** at every scale point.

**The 1 TB/day story is the killer**: $20K/year all-in vs. $58K/year for Cribl. For an SMB, that is the difference between "yes" and "we'll just use rsyslog and bash scripts."

---

## 8. Cost Optimization Opportunities

### Savings Plans / Reserved Instances

| Commitment | Discount | 1 TB/day savings | 10 TB/day savings |
|---|---|---|---|
| 1-year Compute Savings Plan | ~30% on EC2 | $26/mo | $423/mo |
| 3-year Compute Savings Plan | ~50% on EC2 | $44/mo | $705/mo |
| 1-year Reserved (c7g) | ~35% | $31/mo | $494/mo |

At 10 TB/day, a 3-year Savings Plan saves **$8,460/year** on compute alone.

### Spot Instances for Stateless Workers

The architecture routes events through a consistent hash ring with source-node buffering. If a spot node is reclaimed:
- Events buffered on that node's EBS are still there (EBS persists independently of spot lifecycle if configured)
- Actually, no — if the instance terminates, instance store is lost and EBS may or may not be preserved depending on configuration

**Spot is risky for this architecture** because every node owns destinations and holds buffer state. A spot reclamation looks like a node failure — the system handles it, but frequent reclamations would cause constant rebalancing and potential data loss.

**Better approach**: Use spot for dedicated "processing-only" nodes that run pipelines but do not own destinations. This requires architectural support for separating processing from destination ownership — which the current peer model does not have.

**Recommendation**: Do not use spot instances in the initial architecture. Revisit after introducing node roles or stateless processing tiers.

### S3 Intelligent-Tiering

For archive destinations where access patterns are unpredictable (some data gets replayed, most does not), S3 Intelligent-Tiering automatically moves objects between tiers:

- Frequent Access: $0.023/GB
- Infrequent Access (30 days): $0.0125/GB
- Archive Instant Access (90 days): $0.004/GB
- Archive Access (90 days, opt-in): $0.0036/GB
- Deep Archive (180 days, opt-in): $0.00099/GB

Monitoring fee: $0.0025 per 1,000 objects/month.

For a 10 TB/day deployment with 3-month retention, most data lands in Archive Access automatically. **This is better than manually choosing storage classes** because it adapts to actual access patterns.

**Recommendation**: Default S3 destination to Intelligent-Tiering with Archive Access and Deep Archive tiers enabled. This gives near-Glacier pricing without operational complexity.

### Right-Sizing

The BEAM's lightweight processes (2 KB each) mean memory is rarely the bottleneck — CPU is. Use compute-optimized instances (c7g family), not general-purpose (m7g) or memory-optimized (r7g).

Exception: If RocksDB is chosen for the buffer, it benefits from more memory for its block cache. A c7g with 2 GB RAM per core may be tight if RocksDB wants 4–8 GB of cache. Monitor this — if RocksDB cache misses are high, step up to m7g.

---

## 9. Complexity Cost — Where Architecture Adds Hidden Costs

### Consistent Hash Ring + Cross-AZ = Expensive

As shown in Section 4, the hash ring routing model creates cross-AZ traffic that scales linearly with volume. This is the single largest hidden cost in the architecture. At 50 TB/day, it is $13,500/month — more than compute.

**Simplification**: For multi-node deployments, prefer AZ-local processing. Route events to a destination owner in the same AZ. Only cross AZ boundaries for failover. This changes the hash ring from "global ring across all nodes" to "per-AZ ring with cross-AZ failover."

### RocksDB NIF — Operational Complexity

RocksDB via a Rust NIF (Rox) introduces:
- Build complexity (Rust toolchain in CI, cross-compilation for ARM64)
- Crash risk (a NIF segfault takes down the entire BEAM VM, defeating Erlang's fault tolerance)
- Tuning complexity (LSM compaction, block cache sizing, write buffer configuration)
- Upgrade coupling (Rox NIF version must match RocksDB version)

**Alternative**: Consider `dets` (Erlang's built-in disk-based term storage) or Khepri (the new Erlang/OTP distributed data store) for the buffer. They are slower but eliminate the NIF risk entirely. For SMBs at 1 TB/day, the throughput difference may not matter.

If benchmarking shows `dets` cannot keep up, SQLite via Exqlite is a safer NIF bet — SQLite is simpler, more battle-tested, and the Exqlite NIF is mature. RocksDB should be the last resort, not the first choice.

### DynamoDB as Config Store — Operational Simplicity vs. Flexibility

DynamoDB for config is a good choice for AWS-first deployments. However:
- It creates an AWS lock-in for the config layer (not just the data path)
- Local development requires DynamoDB Local (a Java app) or a mock
- Multi-region deployment requires DynamoDB Global Tables (adds cost and complexity)

**For the target market (SMB, AWS-first), this is the right call.** Do not over-engineer for multi-cloud config storage. But consider: an embedded SQLite file for config would eliminate the DynamoDB dependency entirely, work offline, and cost $0. The tradeoff is cluster config consistency — with DynamoDB, all nodes read the same config. With SQLite, you need a config distribution mechanism (which the Erlang cluster already provides).

### Expression Language — Build vs. Adopt Cost

Building a VRL-inspired expression language is a significant engineering investment. Lexer, parser, compiler, type checker, built-in function library, error handling, documentation. This is easily 3–6 months of senior engineer time.

**This is the right long-term decision** (own your expression language, compile to BEAM bytecode, no runtime overhead), but it is the single largest engineering cost in the project. Do not underestimate it.

---

## 10. Specific Recommendations (Prioritized)

### Must-Do (Cost Traps to Avoid)

1. **Default to single-AZ deployments for SMBs.** Cross-AZ data transfer is the largest hidden cost. Document multi-AZ as an HA option with explicit cost warnings. Most SMBs at 1–5 TB/day will take the AZ-failure risk to save $750–$2,000/month.

2. **Use S3 Intelligent-Tiering as the default storage class.** Eliminates the need for customers to choose between Standard and Glacier. Automatically optimizes cost. Prevents the common mistake of storing everything in S3 Standard when 95% of it is never accessed.

3. **Show Glacier restore cost estimates in the UI before initiating replay.** Bill shock from a 10 TB Deep Archive restore ($25–$200 depending on tier) will erode trust faster than any feature can build it. Display: "Estimated restore cost: $X. Estimated time: Y hours. Proceed?"

4. **Set aggressive S3 file size minimums (50–100 MB).** Tiny files multiply PUT costs and S3 request costs. At 50 TB/day with 1 MB files, you are looking at 50 million PUTs/month ($250K/year). At 100 MB files, it is $3K/year. 

5. **Implement DynamoDB TTL on S3 collection state records.** Without TTL, collection state grows unboundedly. A year of 10 TB/day operation creates 30–100 million records. Storage alone would be $750/month. TTL keeps it under free tier.

### Should-Do (Significant Savings)

6. **Graviton-first, always.** 20% cost savings + 50%+ throughput improvement. Build ARM64 as the primary target. This alone saves $2,500/year at 10 TB/day.

7. **Buy 1-year Compute Savings Plans from day one.** Even before you know exact sizing, Compute Savings Plans apply across instance families and sizes. A conservative commitment saves 30% on EC2 with zero risk (you will always use EC2).

8. **Choose SQLite (Exqlite) over RocksDB for the buffer unless benchmarks prove otherwise.** Lower operational complexity, mature NIF, no Rust toolchain dependency. The throughput difference only matters above 10 TB/day, and even then, only for burst scenarios.

9. **Implement AZ-aware hash ring routing.** When multi-AZ deployments are needed, prefer routing to same-AZ destination owners. Only cross AZ for failover. Cuts cross-AZ transfer costs by 60–70%.

### Nice-to-Have (Optimization)

10. **Offer a "cost dashboard" showing AWS spend attributable to compressr.** Use CloudWatch cost allocation tags. SMB CFOs want a single number: "compressr costs us $X/month." If you can show this natively, it builds massive trust.

11. **Support S3 Express One Zone for hot buffers at extreme scale.** S3 Express One Zone delivers single-digit millisecond latency at 50% the request cost of standard S3. At 50 TB/day, this saves on PUT costs for staging files.

12. **Explore BEAM-native buffering (ETS + periodic disk flush) for the simple case.** At 1 TB/day, the buffer requirements are modest (~12 MB/s sustained write). ETS tables with periodic flush to a simple file could eliminate the buffer engine dependency entirely for single-node deployments.

---

## Summary for the CFO Conversation

**"How much does this cost us per month?"**

| Volume | Compressr Monthly Cost (infra only) | Compressr Monthly Cost (with ops) | Cribl Monthly Cost (license + ops) |
|---|---|---|---|
| 1 TB/day | $205 | $1,670 | $4,800 |
| 5 TB/day | $1,095 | $4,720 | $14,200 |
| 10 TB/day | $2,730 | $10,020 | $25,800 |
| 50 TB/day | $11,650 | $33,540 | $66,700 |

**"Is it worth it vs. just paying Cribl?"**

At 1 TB/day: Compressr saves **$37K/year** even including operational costs. If you have any DevOps capacity at all, the answer is yes.

At 10 TB/day: Compressr saves **$190K/year**. That is a full engineering headcount. Yes.

At 50 TB/day: Compressr saves **$398K/year**. But you need a 1.5-person SRE team to run it. If you already have SRE staff, it is a no-brainer. If you do not, the Cribl premium buys you operational simplicity.

**The single biggest cost risk** is cross-AZ data transfer at multi-node scale. Default to single-AZ deployments and make this an explicit, documented architectural decision. The second biggest risk is S3 request costs from undersized files — enforce minimum file sizes.
