# Fixtures

Hand-written payloads that mirror the shape of Yahoo Finance's
`/v8/finance/chart` and `/v1/finance/search` responses, trimmed to the fields
this app reads plus the awkward cases it has to survive (null gaps in the
close array, a missing `longName`, an upstream error object).

They are not verbatim captures — they were authored from the documented
response shape rather than recorded from a live call. If a parser starts
misreading real data, replace these with a real capture:

    curl -s -H 'User-Agent: Mozilla/5.0' \
      'https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m' \
      > chart-1d.json
