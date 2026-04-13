# Design Decisions

Manifold is the user-owned control plane that sits beside Claude and Codex, recording what they actually saw and changed on your Mac, across sessions and across vendors.

These are the main decisions behind the current product shape.

## Why A Local Runtime Instead Of A Hosted Service

The product promise is local ownership:

- the user owns the record
- audit and history live on the Mac
- trust does not depend on a vendor dashboard or cloud service

That is why Manifold uses a local runtime plus a native app instead of a hosted control plane.

## Why Standing Access And Tracked Work Blocks

Reads and edits deserve different levels of friction.

- `Standing Access` keeps read/search workflows simple and auditable.
- `Tracked Work Blocks` add snapshots, review, restore, promote, and discard for edits.

This is why Manifold does not treat every file access as a heavy review workflow and does not treat every write as a casual read.

## Why Managed Workspaces Instead Of Pretending To Block Everything

Claude Desktop / Cowork and Codex expose local capability differently. A completely universal OS-level gate is not what V1 honestly offers.

So Manifold chooses:

- governed reads/searches through the Manifold path
- tracked workspaces for governed edits
- explicit coverage states for what is and is not under control

That is a more honest product than claiming total machine enforcement.

## Why SQLite Plus A Blob Store

The runtime stores different kinds of data with different needs:

- SQLite is a good fit for policy, audit events, exposure records, summaries, and indexes.
- content-addressed blobs are a good fit for immutable file versions and snapshot payloads.

This gives Manifold:

- local durability
- easy indexing and querying
- efficient deduplication for tracked history

## Why Record Exposure, Not Just Requests

Knowing that an agent asked for `foo.txt` is weaker than knowing what Manifold actually returned.

Manifold records:

- access decisions
- exposure records
- tracked changes
- version history
- session context

That is what makes the app useful as a real system of record instead of a thin permission layer.

## Why MCP First

MCP is the most practical vendor-neutral path for Claude Desktop and Codex right now.

It lets Manifold:

- support both apps with one integration model
- keep the adapter thin
- keep the runtime as the real source of truth

The long-term architecture is runtime-first, not protocol-first, but MCP is the right V1 edge.

## Why History Is A Core Feature

AI work is rarely one session long.

The durable value of Manifold is that later work can build on:

- what was shared
- what was actually exposed
- what changed
- what else happened around that change

That is why Manifold treats version history and session context as product pillars, not just internal implementation details.
