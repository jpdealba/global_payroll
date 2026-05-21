I’m currently in the final interview stage for a Sr. Software Engineer (Elixir) role at AlertMedia. AlertMedia is a company focused on emergency communication, mass notifications, and critical event management systems used by organizations to communicate quickly during incidents or operational disruptions. Their engineering environment appears heavily backend/distributed-systems oriented, with strong emphasis on scalability, reliability, asynchronous processing, and real-time systems. The interview process so far has included an HR screen and a technical conversation with an Engineering Manager that was more discussion-based than algorithm-heavy. The final interview is a 1-hour Virtual Technical Interview scheduled for Friday, May 22, 2026, from 12:00pm–1:00pm (GMT-06 Guadalajara), with Rodrigo Medina (Senior Software Engineer), Jim Kirkbride (Senior Software Engineer), Jason Do (Senior Software Engineer), and Kyle Witt (Senior Manager, Software Engineering). Their email explicitly mentioned that they value “curious engineers” and encouraged questions about architecture, systems, team challenges, and scaling.

For the interview, I’ll present and walk through a personal distributed systems project called “Global Payroll,” built mainly with Elixir/Phoenix, Broadway, and SQS. The project simulates large-scale payroll/payment orchestration and focuses on concurrency, batching, retries, idempotency, asynchronous processing, webhook reconciliation, and fault tolerance. The system currently processes around 100k payment simulations in a little over 4 minutes, where “payments” are synchronous simulated provider responses from a function I built (not real external payment execution). I’ve experimented with Broadway concurrency, batching strategies, SQS polling intervals, multi-node scaling, database bottlenecks, bulk inserts, PgBouncer, and throughput optimization. The goal of the presentation is not just to show code, but to demonstrate architecture decisions, tradeoffs, debugging process, scalability considerations, and understanding of distributed backend systems.


Study structure:
Wednesday:
	1- Tests [x]
	2- Review Architecture and sequence diagrams and api design (45 min) [x]
	3- Review scalability and fault tolerance (45 min) 
	4- Make a plan for the interview (like a script) maybe use a tool like paint or draw.io to create a diagram of the project while explaining it (120 min)
	5- Review the project and the code (120 min)

Thursday:
	1- Define possible bottlenecks and how to solve them (60 min)
	   - Include decisions NOT taken and why: SQS vs Kafka or Oban, single node vs multi-node, flat DB vs sharding
	   - Include "what would change at 10x / 100x load?" answers
	   - Include multi-tenant / real-world productionization gaps
	2- Define past challenges and how to solve them (45 min)
	3- OTP/BEAM fundamentals tied to the project (30 min)
	   - What supervises the Broadway pipeline? What happens if a worker crashes?
	   - GenServer vs Task vs Broadway — why each was or wasn't used
	   - Process model: how Broadway workers are isolated, mailbox, backpressure
	4- Define some questions that they may ask me (30 min)
	5- Define some questions that I may ask them (30 min)
	6- Review the architecture and the code (30 min)
	7- Review the script and the diagram (60 min)
	8- Dry run: present the project out loud, timed (30 min)
	   - Target: walkthrough in ~20 min, leaving 40 min for Q&A with 4 interviewers
	   - If it runs over, cut — don't speed up

---

## Architecture Concepts

### Event Sourcing
Instead of storing current state, you store the immutable events that generated it and derive state by replaying them.

The ledger in this project IS event sourcing:
- Never `UPDATE balance = balance - 100`
- Instead: `INSERT { type: "payroll_deduction", amount: -100 }`
- Balance is always derived: `SELECT SUM(amount) FROM company_transactions`
- Immutable events, full audit trail, derived state — that's event sourcing

Applied only to money movement, not to the entire system (payroll run status is still mutable state).

### CQRS (Command Query Responsibility Segregation)
Separates writes and reads into distinct models — typically two separate databases.

- **Write side**: receives commands → stores events → state changes
- **Read side**: a pre-computed projection optimized for fast reads (denormalized, aggregated)

**When it makes sense:** reads and writes have very different scale requirements, or you use full event sourcing and need projections to query current state efficiently without replaying all events.

**The cost it introduces:**
- Two models to keep in sync — if projection fails, reads return stale data
- Eventual consistency between write and read DB
- Much more infrastructure: event store, projection workers, possibly Kafka
- Harder to debug

**This project does not use CQRS** — one PostgreSQL, state updated directly. The ledger's `SUM(amount)` query is fast enough without a projection.

**How to answer if asked in the interview:**
> "The ledger already uses event sourcing where it matters — financial audit trail. For payroll run status, the write volume doesn't justify maintaining separate projections. At millions of concurrent runs with heavy reads, that's when separating would make sense — but it's a scale decision, not a base architecture one."