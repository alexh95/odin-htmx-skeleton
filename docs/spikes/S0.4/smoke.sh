#!/usr/bin/env sh
# Spike S0.4: functional smoke of one running candidate. Not a measurement.
#
#   docs/spikes/S0.4/smoke.sh [BASE_URL]        (default http://127.0.0.1:8080)
#
# Expects a fresh seeded store (20 contacts). Checks /healthz; the contacts list
# sorted (name, name_desc, email_desc, score), paged and filtered; the search
# fragment and the JSON API; a create, an edit, an edit from the drawer, a
# status cycle and a delete, each answered with the stored row; the 422 and 404
# paths; /forms/submit; the dashboard's total against the table's count (how
# long it lagged, for candidate A's cached aggregate); and 40 concurrent creates
# and deletes that must each answer with their own row (candidate C's batches).
# Prints one line per check and exits 1 if any failed.
set -u
B="${1:-http://127.0.0.1:8080}"
FORM='Content-Type: application/x-www-form-urlencoded'
fails=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$3], got [$2]"; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then ok "$1"; else bad "$1: no [$3] in [$(printf '%s' "$2" | head -c 300)]"; fi; }
get() { curl -s "$B$1"; }
post() { curl -s -X POST -H "$FORM" --data "$2" "$B$1"; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
names() { grep -o '<strong>[^<]*</strong><small>#' | sed 's/<strong>//; s/<\/strong><small>#//'; }
emails() { grep -o '<td class="c-email">[^<]*</td>' | sed 's/<td class="c-email">//; s/<\/td>//'; }
scores() { grep -o '<small>[0-9]*</small></td>' | sed 's/<small>//; s/<\/small><\/td>//'; }
table_count() { get /data | grep -o '<span class="muted">[0-9]* contacts*</span>' | grep -o '[0-9]*'; }
dash_count() { get / | grep -o 'Total contacts</span></div><div class="stat-value" data-count="[0-9]*"' | grep -o '[0-9]*"$' | tr -d '"'; }
new_id() { grep -o 'hx-delete="/contacts/[0-9]*"' | head -1 | grep -o '[0-9]*'; }

check "healthz" "$(get /healthz)" "ok"
check "x-version names the build" "$(curl -s -o /dev/null -D - "$B/healthz" | grep -i '^x-version' | tr -d '\r' | sed 's/^[^:]*: //' | cut -c1-4)" "s04-"
check "seeded store" "$(table_count)" "20"
check "dashboard total, before any write" "$(dash_count)" "20"

# ---- lists: sorted, paged, filtered --------------------------------------
p1=$(get '/contacts?sort=name&page=1')
check "page 1 has 7 rows" "$(printf '%s' "$p1" | names | wc -l | tr -d ' ')" "7"
all=$(for p in 1 2 3; do get "/contacts?sort=name&page=$p" | names; done)
check "name sort across 3 pages" "$(printf '%s\n' "$all" | LC_ALL=C sort | tr '\n' '|')" "$(printf '%s\n' "$all" | tr '\n' '|')"
check "3 pages hold all 20, none twice" "$(printf '%s\n' "$all" | sort -u | wc -l | tr -d ' ')" "20"
desc=$(for p in 1 2 3; do get "/contacts?sort=name_desc&page=$p" | names; done)
check "name_desc is name reversed" "$(printf '%s\n' "$desc" | tr '\n' '|')" "$(printf '%s\n' "$all" | LC_ALL=C sort -r | tr '\n' '|')"
em=$(get '/contacts?sort=email_desc&page=1' | emails)
check "email_desc sort" "$(printf '%s\n' "$em" | tr '\n' '|')" "$(printf '%s\n' "$em" | LC_ALL=C sort -r | tr '\n' '|')"
sc=$(for p in 1 2 3; do get "/contacts?sort=score&page=$p" | scores; done)
if printf '%s\n' "$sc" | sort -n -c 2>/dev/null; then ok "score sort across pages"; else bad "score sort: $(printf '%s ' $sc)"; fi
act=$(get '/contacts?status=Active&sort=name')
check "status filter: only Active rows" "$(printf '%s' "$act" | grep -o 'badge-[a-z]*' | sort -u | tr '\n' ' ')" "badge-ok "
check "page past the end clamps" "$(get '/contacts?sort=name&page=99' | names | head -1)" "$(printf '%s\n' "$all" | sed -n 15p)"

# ---- search ---------------------------------------------------------------
has "search fragment, highlighted" "$(get '/search?q=grace')" "<mark>Grace</mark> Hopper"
has "JSON API" "$(get '/api/search?q=hopper')" '"name":"Grace Hopper","email":"grace.hopper@example.dev"'
check "search miss" "$(get '/api/search?q=no-such-person')" "[]"

# ---- writes, each answered with the stored row ----------------------------
r=$(post /contacts 'name=Smoke+Test&email=smoke.test%40example.dev&role=Designer')
id=$(printf '%s' "$r" | new_id)
has "create answers the new row" "$r" '<strong>Smoke Test</strong><small>#'"$id"'</small>'
has "create answers the toast" "$r" 'Contact added.'
check "create counted" "$(table_count)" "21"
has "detail of the new row" "$(get "/contacts/$id")" "smoke.test@example.dev"
r=$(post "/contacts/$id" 'name=Smoke+Edited&email=smoke.edited%40example.dev&role=Manager&status=Active&score=77')
has "edit answers the stored row" "$r" '<strong>Smoke Edited</strong>'
has "edit answers the stored score" "$r" '<small>77</small>'
has "edit stored" "$(get '/api/search?q=smoke.edited')" '"role":"Manager","status":"Active","score":77'
r=$(post "/contacts/$id" 'name=Smoke+Drawer&email=smoke.edited%40example.dev&role=Manager&status=Active&score=78&view=detail')
has "drawer edit answers drawer + hx-partial row" "$r" "<hx-partial hx-target=\"#contact-$id\""
r=$(post "/contacts/$id" 'action=cycle')
has "cycle answers the next status" "$r" 'badge-warn"><i class="dot"></i>Invited'
has "cycle stored" "$(get '/api/search?q=smoke.edited')" '"status":"Invited"'
check "plain POST answers the row unchanged" "$(post "/contacts/$id" '' | names)" "Smoke Drawer"
check "create: bad email is 422" "$(status -X POST -H "$FORM" --data 'name=X&email=bad' "$B/contacts")" "422"
check "edit: bad email is 422" "$(status -X POST -H "$FORM" --data 'name=Y&email=bad&view=detail' "$B/contacts/$id")" "422"
check "edit of a missing id is 404" "$(status -X POST -H "$FORM" --data 'name=Z&email=z%40example.dev' "$B/contacts/99999999")" "404"
check "cycle of a missing id is 404" "$(status -X POST -H "$FORM" --data 'action=cycle' "$B/contacts/99999999")" "404"
r=$(post /forms/submit 'name=Form+Smoke&email=form.smoke%40example.dev&role=Sales&status=Active&score=33&notes=hello+there&notify=on')
has "forms/submit answers the stored row" "$r" 'Form Smoke · form.smoke@example.dev · saved as #'
has "forms/submit stored notes and notify" "$(get '/api/search?q=form.smoke')" '"notes":"hello there","notify":true'

# ---- the dashboard against the table, right after a write ------------------
dash_count > /dev/null
did=$(post /contacts 'name=Dash+Probe&email=dash.probe%40example.dev&role=Sales' | new_id)
want=$(table_count)
waited=0
while [ "$(dash_count)" != "$want" ] && [ $waited -lt 30 ]; do sleep 0.1; waited=$((waited + 1)); done
check "dashboard total = table count after a write (lagged $((waited * 100)) ms)" "$(dash_count)" "$want"
curl -s -o /dev/null -X DELETE "$B/contacts/$did"

# ---- delete ----------------------------------------------------------------
check "delete" "$(curl -s -X DELETE -w '%{http_code}' "$B/contacts/$id")" "200"
check "delete again is 404" "$(status -X DELETE "$B/contacts/$id")" "404"
check "deleted row is gone" "$(status "$B/contacts/$id")" "404"
fid=$(get '/api/search?q=form.smoke' | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
has "delete from the drawer answers the OOB row" "$(curl -s -X DELETE "$B/contacts/$fid?from=drawer")" "<tr id=\"contact-$fid\" hx-swap-oob=\"delete\">"

# ---- concurrent writes: each answer is its own row -------------------------
before=$(table_count)
i=0
while [ $i -lt 40 ]; do
  curl -s -X POST -H "$FORM" --data "name=Par+$i&email=par$i%40example.dev&role=Support" "$B/contacts" > "$TMP/c$i" &
  i=$((i + 1))
done
wait
own=0
i=0
while [ $i -lt 40 ]; do
  grep -q "<strong>Par $i</strong>" "$TMP/c$i" && own=$((own + 1))
  new_id < "$TMP/c$i" >> "$TMP/ids"
  i=$((i + 1))
done
check "40 concurrent creates answer their own rows" "$own" "40"
check "40 distinct ids" "$(sort -u "$TMP/ids" | wc -l | tr -d ' ')" "40"
check "40 rows stored" "$(table_count)" "$((before + 40))"
for d in $(cat "$TMP/ids"); do
  curl -s -o /dev/null -w '%{http_code}\n' -X DELETE "$B/contacts/$d" > "$TMP/d$d" &
done
wait
check "40 concurrent deletes" "$(cat "$TMP"/d* | grep -c '^200$')" "40"
check "back to the count before" "$(table_count)" "$before"

echo "$fails failed"
[ "$fails" -eq 0 ]
