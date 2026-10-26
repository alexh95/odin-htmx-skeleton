/* S0.11: what each tuned flag changes, observed through the C API.
 *   clang traps.c -I<dir with sqlite3.h> <sqlite3.lib|sqlite3.a> [-lpthread -lm] -o traps
 * Prints one "name: value" line per check; run it against the default and the
 * tuned lib and compare. */
#include <stdio.h>
#include "sqlite3.h"

static int one_int(sqlite3 *db, const char *sql, int *out, const char **err) {
	sqlite3_stmt *st = 0;
	int rc = sqlite3_prepare_v2(db, sql, -1, &st, 0);
	if (rc != SQLITE_OK) { *err = sqlite3_errmsg(db); return rc; }
	rc = sqlite3_step(st);
	if (rc == SQLITE_ROW) { *out = sqlite3_column_int(st, 0); rc = SQLITE_OK; }
	else *err = sqlite3_errmsg(db);
	sqlite3_finalize(st);
	return rc;
}

int main(void) {
	static const char *opts[] = {"DQS=0", "DEFAULT_FOREIGN_KEYS", "THREADSAFE=2", "DEFAULT_MEMSTATUS=0",
		"OMIT_LOAD_EXTENSION", "OMIT_SHARED_CACHE", "ENABLE_FTS5", 0};
	printf("version: %s\n", sqlite3_libversion());
	printf("sqlite3_threadsafe(): %d\n", sqlite3_threadsafe());
	for (int i = 0; opts[i]; i++) printf("compileoption %s: %d\n", opts[i], sqlite3_compileoption_used(opts[i]));

	sqlite3 *db = 0;
	const char *err = "";
	int v = -1;
	sqlite3_open(":memory:", &db);

	/* DEFAULT_FOREIGN_KEYS=1: a fresh connection enforces foreign keys. */
	one_int(db, "PRAGMA foreign_keys", &v, &err);
	printf("PRAGMA foreign_keys on a fresh connection: %d\n", v);

	/* DQS=0: a double-quoted string is an identifier, never a string literal. */
	v = -1;
	int rc = one_int(db, "SELECT length(\"abc\")", &v, &err);
	printf("SELECT length(\"abc\"): %s\n", rc == SQLITE_OK ? "3 (taken as the string 'abc')" : err);

	/* ENABLE_FTS5. */
	rc = sqlite3_exec(db, "CREATE VIRTUAL TABLE f USING fts5(body, tokenize='unicode61 remove_diacritics 2');"
	                      "INSERT INTO f VALUES('Café au lait');", 0, 0, 0);
	if (rc == SQLITE_OK) {
		v = -1;
		one_int(db, "SELECT count(*) FROM f WHERE f MATCH 'cafe'", &v, &err);
		printf("fts5 MATCH 'cafe' on 'Café au lait': %d row(s)\n", v);
	} else printf("fts5: %s\n", sqlite3_errmsg(db));

	/* DEFAULT_MEMSTATUS=0: the global counters stop; per-connection ones still work. */
	sqlite3_exec(db, "CREATE TABLE t(x); WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM c WHERE i<5000)"
	                 " INSERT INTO t SELECT randomblob(100) FROM c;", 0, 0, 0);
	printf("sqlite3_memory_used(): %lld B\n", (long long)sqlite3_memory_used());
	int cur = 0, hi = 0;
	sqlite3_db_status(db, SQLITE_DBSTATUS_CACHE_USED, &cur, &hi, 0);
	printf("sqlite3_db_status(CACHE_USED): %d B\n", cur);
	sqlite3_close(db);

	/* OMIT_SHARED_CACHE: two connections to one cache=shared URI. */
	const char *uri = "file:s011?mode=memory&cache=shared";
	sqlite3 *a = 0, *b = 0;
	int fl = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI;
	printf("open a: %d, open b: %d\n", sqlite3_open_v2(uri, &a, fl, 0), sqlite3_open_v2(uri, &b, fl, 0));
	sqlite3_exec(a, "CREATE TABLE shared_t(x); INSERT INTO shared_t VALUES(1);", 0, 0, 0);
	v = -1;
	rc = one_int(b, "SELECT count(*) FROM shared_t", &v, &err);
	if (rc == SQLITE_OK) printf("cache=shared, b reads a's table: %d row(s)\n", v);
	else printf("cache=shared, b reads a's table: %s\n", err);
	sqlite3_close(a);
	sqlite3_close(b);
	return 0;
}
