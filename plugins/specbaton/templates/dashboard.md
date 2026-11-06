# Dashboard

A live view of decisions and work in progress, built by Dataview from the files. Don't edit it by hand.
Sources: [NOW](NOW.md) · [Decision index](decisions/README.md)

## ADRs in force by unit

```dataview
TABLE WITHOUT ID
  repo AS Unit,
  rows.file.link AS ADR,
  map(rows.date, (d) => dateformat(d, "yyyy-MM-dd")) AS Date
FROM "decisions"
WHERE status = "accepted"
FLATTEN repos AS repo
GROUP BY repo
SORT repo ASC
```

## To complete

ADRs with something marked [UNCERTAIN]. Once it's complete, remove the `uncertain` property.

```dataview
TABLE WITHOUT ID
  file.link AS ADR,
  uncertain AS "What's missing",
  repos AS Units
FROM "decisions"
WHERE uncertain
SORT file.name ASC
```

## ADRs by ticket

```dataview
TABLE WITHOUT ID
  ticket AS Ticket,
  length(rows) AS ADRs,
  rows.file.link AS Decisions
FROM "decisions"
WHERE status = "accepted"
FLATTEN tickets AS ticket
GROUP BY ticket
SORT ticket ASC
```

## Proposals waiting to be accepted

```dataview
TABLE WITHOUT ID
  file.link AS ADR,
  repos AS Units,
  dateformat(date, "yyyy-MM-dd") AS Date
FROM "decisions"
WHERE status = "proposed"
SORT date DESC
```

## State of the active changes

```dataview
TABLE WITHOUT ID
  link(file.path, file.folder) AS Change,
  dateformat(file.mtime, "yyyy-MM-dd") AS Updated
FROM "openspec/changes"
WHERE file.name = "status" AND !contains(file.path, "/archive/")
SORT file.mtime DESC
```

## Open tasks by change

```dataview
TASK
FROM "openspec/changes"
WHERE !completed AND !contains(file.path, "/archive/")
GROUP BY file.folder
```

## Superseded decisions

```dataview
TABLE WITHOUT ID
  file.link AS ADR,
  superseded_by AS "Superseded by",
  dateformat(date, "yyyy-MM-dd") AS Date
FROM "decisions"
WHERE status = "superseded"
SORT date DESC
```

## Recently changed docs

```dataview
TABLE WITHOUT ID
  file.link AS Document,
  dateformat(file.mtime, "yyyy-MM-dd") AS Changed
FROM "docs"
SORT file.mtime DESC
LIMIT 10
```
