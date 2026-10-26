-- One index per sort key of the contacts table (order_by in store.odin),
-- each ending in id, the tie-break every page sorts by: a page is then read in
-- order from its index instead of sorting every row that passed the filter.
-- Role and status sort by their label's A-to-Z rank, so theirs are on the same
-- CASE expression order_by builds from the label tables; the store's test
-- fails if a page statement stops using its index.
CREATE INDEX IF NOT EXISTS idx_contacts_by_name   ON contacts(name, id);
CREATE INDEX IF NOT EXISTS idx_contacts_by_email  ON contacts(email, id);
CREATE INDEX IF NOT EXISTS idx_contacts_by_score  ON contacts(score, id);
CREATE INDEX IF NOT EXISTS idx_contacts_by_role   ON contacts((CASE role WHEN 0 THEN 1 WHEN 1 THEN 0 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 4 END), id);
CREATE INDEX IF NOT EXISTS idx_contacts_by_status ON contacts((CASE status WHEN 0 THEN 0 WHEN 1 THEN 2 WHEN 2 THEN 1 END), id);
