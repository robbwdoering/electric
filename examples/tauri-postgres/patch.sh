#!/bin/bash

# This is a script that solves inconsistencies for the tauri linearlite demo
# At the end of the demo, this file should be empty

# sed -i 's/WITHOUT ROWID//g' src/generated/client/migrations.ts
# sed -i '' 's/WITHOUT ROWID//g' src/generated/client/migrations.ts
sed 's/WITHOUT ROWID//g' src/generated/client/migrations.ts > tmpfile && mv tmpfile src/generated/client/migrations.ts
