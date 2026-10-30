package store_sqlite

// ---- migrations, per feature --------------------------------------------------
//
// PLAN §11.7, the runner research 12 §5 tested. Each applied migration is keyed
// (feature, seq, name, sha256) in schema_migrations; schema_meta records the app
// and the profile that own the file, and the header's application_id says it is
// ours. At open (check_identity) the runner refuses:
//   - a database another application stamped;
//   - user tables with no migration records (not ours);
//   - another profile's database, unless started once with --adopt-profile.
// A database the skeleton wrote (709bc94, v1.1.1; schema_version, no
// application_id) is adopted by the `legacy` feature when it migrates: its rows
// become that feature's, hashes checked (v1.1.1 recorded none, and is trusted),
// and schema_version stays as it was, so the old binary still recognises the
// file. Rows of features this build doesn't migrate are left alone (dormant).
// Each `migrate` call verifies its feature's rows, then applies what is pending,
// one transaction per migration with its record, in main's order.

import "core:crypto/sha2"
import "core:encoding/hex"
import "core:fmt"
import "core:strings"

import store ".."
import "../../guard"
import "../../obs"
import "../../sqlite"
import "../../sys"

@(private)
mig: struct {
	legacy:         string, // the feature that adopts schema_version's rows
	legacy_pending: bool,   // schema_version exists and is not adopted yet
}

@(private)
check_identity :: proc(profile, legacy: string, adopt_profile: bool) -> (problem: string) {
	w := db.writer.db
	must(w, "BEGIN IMMEDIATE")
	app_id := scalar(w, "PRAGMA application_id")
	has_versions := scalar(w, "SELECT count(*) FROM sqlite_schema WHERE type='table' AND name='schema_version'") > 0
	has_migs := scalar(w, "SELECT count(*) FROM sqlite_schema WHERE type='table' AND name='schema_migrations'") > 0
	user_tables := scalar(w, "SELECT count(*) FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'")

	switch {
	case app_id != 0 && app_id != APP_ID:
		problem = fmt.tprintf("this database belongs to another application (application_id 0x%08x, this app is 0x%08x). Point DB_PATH at its own file.", u32(app_id), u32(APP_ID))
	case app_id == 0 && !has_versions && !has_migs && user_tables > 0:
		problem = fmt.tprintf("this database has %d tables but no migration records: it wasn't written by this app. Point DB_PATH at its own file.", user_tables)
	case app_id == 0 && has_migs:
		problem = "schema_migrations exists but the header has no application_id: refusing a half-initialised or foreign database."
	case app_id == 0 && has_versions && legacy == "":
		problem = "this database was written by the odin-htmx-skeleton (schema_version) and this profile adopts none of its features. Point DB_PATH at its own file."
	}
	if problem != "" {
		sqlite.exec(w, "ROLLBACK")
		return
	}

	must(w, `CREATE TABLE IF NOT EXISTS schema_migrations (
		feature TEXT NOT NULL, seq INTEGER NOT NULL, name TEXT NOT NULL, sha256 TEXT NOT NULL,
		applied_at INTEGER NOT NULL, PRIMARY KEY (feature, seq)) WITHOUT ROWID`)
	must(w, "CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID")

	if app_id == 0 {
		must(w, fmt.ctprintf("PRAGMA application_id=%d", APP_ID))
		set_meta("app", APP_NAME)
		set_meta("profile", profile)
		mig.legacy, mig.legacy_pending = legacy, has_versions
	} else {
		if app := get_meta("app"); app != APP_NAME {
			sqlite.exec(w, "ROLLBACK")
			return fmt.tprintf("this database belongs to app %q, not %q.", app, APP_NAME)
		}
		if owner := get_meta("profile"); owner != profile {
			if !adopt_profile {
				sqlite.exec(w, "ROLLBACK")
				return fmt.tprintf("this database belongs to profile %q; this binary is profile %q. Give each profile its own DB_PATH, or start once with --adopt-profile to move it to %q on purpose.", owner, profile, profile)
			}
			set_meta("profile", profile)
			set_meta(fmt.tprintf("adopted_from_%d", sys.now_unix_ns() / 1e9), owner)
		}
	}
	must(w, "COMMIT")
	return ""
}

// Verifies `feature`'s recorded migrations against `migrations` and applies the
// pending ones. A problem stops the boot with a message naming it.
migrate :: proc(feature: string, migrations: []store.Migration) {
	if problem := apply(feature, migrations); problem != "" {
		fatal("migrations: %s", problem)
	}
	for m in migrations { append(&store.in_force, store.In_Force{feature, m.seq, m.name}) }
}

@(private)
apply :: proc(feature: string, migrations: []store.Migration) -> (problem: string) {
	w := db.writer.db
	for m, i in migrations {
		if m.seq != i + 1 { return fmt.tprintf("%s's MIGRATIONS should count 1, 2, 3…; %s is #%d at position %d", feature, m.name, m.seq, i + 1) }
	}
	guard.lock(&db.wlock)
	defer guard.unlock(&db.wlock)

	must(w, "BEGIN IMMEDIATE")
	if mig.legacy_pending && feature == mig.legacy {
		if problem = adopt(feature, migrations); problem != "" {
			sqlite.exec(w, "ROLLBACK")
			return
		}
		mig.legacy_pending = false
	}
	done := 0
	{
		st := prep("SELECT seq, name, sha256 FROM schema_migrations WHERE feature=? ORDER BY seq")
		defer sqlite.finalize(st)
		sqlite.bind_text(st, 1, feature)
		for sqlite.step(st) == sqlite.ROW {
			seq, name, hash := sqlite.column_int(st, 0), text(st, 1), text(st, 2)
			if seq != done + 1 || seq > len(migrations) {
				sqlite.exec(w, "ROLLBACK")
				return fmt.tprintf("the database has %s migration #%d (%s), which this binary doesn't: it was written by a newer build. Point DB_PATH at its own file.", feature, seq, name)
			}
			m := migrations[seq - 1]
			if want := migration_hash(m.sql); name != m.name || hash != want {
				sqlite.exec(w, "ROLLBACK")
				return fmt.tprintf("%s migration #%d was applied as %s (sha256 %s) but this binary has %s (sha256 %s). An applied migration must never change: add a new one instead. For a dev database built by another schema, move it aside.", feature, seq, name, hash[:min(12, len(hash))], m.name, want[:12])
			}
			done = seq
		}
	}
	must(w, "COMMIT")

	for m in migrations[done:] {
		must(w, "BEGIN IMMEDIATE")
		if sqlite.exec(w, strings.clone_to_cstring(m.sql, context.temp_allocator)) != sqlite.OK {
			problem = fmt.tprintf("%s/%s failed: %s. Rolled back; the schema is unchanged.", feature, m.name, sqlite.errmsg(w))
			sqlite.exec(w, "ROLLBACK")
			return
		}
		if !record(feature, m) {
			problem = fmt.tprintf("recording %s/%s failed: %s", feature, m.name, sqlite.errmsg(w))
			sqlite.exec(w, "ROLLBACK")
			return
		}
		must(w, "COMMIT")
		if l, ok := obs.begin(.Info, "store", "migrated"); ok {
			obs.str(&l, "feature", feature)
			obs.str(&l, "name", m.name)
			obs.end(&l)
		}
	}
	return ""
}

// The skeleton's schema_version rows become `feature`'s: 709bc94 recorded names
// and hashes, which must match; v1.1.1 recorded only numbers, and is trusted as
// the skeleton trusted it.
@(private)
adopt :: proc(feature: string, migrations: []store.Migration) -> string {
	w := db.writer.db
	has_hash := scalar(w, "SELECT count(*) FROM pragma_table_info('schema_version') WHERE name='hash'") > 0
	st := prep("SELECT version, name, hash FROM schema_version ORDER BY version" if has_hash else "SELECT version, NULL, NULL FROM schema_version ORDER BY version")
	defer sqlite.finalize(st)
	n := 0
	for sqlite.step(st) == sqlite.ROW {
		version := sqlite.column_int(st, 0)
		if version != n + 1 { return fmt.tprintf("schema_version should count 1, 2, 3…; found #%d where #%d belongs", version, n + 1) }
		if n >= len(migrations) { return fmt.tprintf("the database has skeleton migration #%d, which this binary's %q doesn't.", version, feature) }
		m := migrations[n]
		if sqlite.column_type(st, 2) != sqlite.NULL {
			name, hash, want := text(st, 1), text(st, 2), migration_hash(m.sql)
			if name != m.name || hash != want {
				return fmt.tprintf("skeleton migration #%d was applied as %s (sha256 %s) but this binary's %q has %s (sha256 %s).", version, name, hash[:min(12, len(hash))], feature, m.name, want[:12])
			}
		}
		if !record(feature, m) { return fmt.tprintf("adopting migration #%d failed: %s", version, sqlite.errmsg(w)) }
		n += 1
	}
	set_meta("adopted_from", "odin-htmx-skeleton")
	if l, ok := obs.begin(.Info, "store", "adopted"); ok {
		obs.str(&l, "feature", feature)
		obs.num(&l, "migrations", i64(n))
		obs.end(&l)
	}
	return ""
}

@(private)
record :: proc(feature: string, m: store.Migration) -> bool {
	st := prep("INSERT INTO schema_migrations(feature, seq, name, sha256, applied_at) VALUES(?,?,?,?,?)")
	defer sqlite.finalize(st)
	sqlite.bind_text(st, 1, feature)
	sqlite.bind_int(st, 2, m.seq)
	sqlite.bind_text(st, 3, m.name)
	sqlite.bind_text(st, 4, migration_hash(m.sql))
	sqlite.bind_int64(st, 5, sys.now_unix_ns() / 1e9)
	return sqlite.step(st) == sqlite.DONE
}

// sha256 of the SQL, hex, carriage returns dropped first, so a CRLF checkout hashes
// as the LF one that wrote the record: the skeleton's migration_hash, unchanged,
// so the hashes it recorded stay valid.
migration_hash :: proc(sql: string) -> string {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	rest := sql
	for len(rest) > 0 {
		cr := strings.index_byte(rest, '\r')
		chunk := rest if cr < 0 else rest[:cr]
		sha2.update(&ctx, transmute([]byte)chunk)
		rest = "" if cr < 0 else rest[cr + 1:]
	}
	sum: [sha2.DIGEST_SIZE_256]byte
	sha2.final(&ctx, sum[:])
	return string(hex.encode(sum[:], context.temp_allocator))
}

// ---- one-shot statements on the writer (boot only) ------------------------------

@(private)
prep :: proc(sql: string) -> Stmt {
	st, rc := sqlite.prepare(db.writer.db, sql)
	if rc != sqlite.OK { fatal("store: can't prepare %q: %s", sql, sqlite.errmsg(db.writer.db)) }
	return st
}

@(private)
scalar :: proc(conn: sqlite.DB, sql: string) -> int {
	st, rc := sqlite.prepare(conn, sql)
	if rc != sqlite.OK { fatal("store: can't prepare %q: %s", sql, sqlite.errmsg(conn)) }
	defer sqlite.finalize(st)
	return sqlite.column_int(st, 0) if sqlite.step(st) == sqlite.ROW else 0
}

@(private)
text :: proc(st: Stmt, col: int) -> string {
	return strings.clone(sqlite.column_text(st, col), context.temp_allocator)
}

@(private)
set_meta :: proc(key, value: string) {
	st := prep("INSERT INTO schema_meta(key, value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
	defer sqlite.finalize(st)
	sqlite.bind_text(st, 1, key)
	sqlite.bind_text(st, 2, value)
	sqlite.step(st)
}

@(private)
get_meta :: proc(key: string) -> string {
	st := prep("SELECT value FROM schema_meta WHERE key=?")
	defer sqlite.finalize(st)
	sqlite.bind_text(st, 1, key)
	return text(st, 0) if sqlite.step(st) == sqlite.ROW else ""
}
