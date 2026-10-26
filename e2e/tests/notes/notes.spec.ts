import { test, expect } from '../../fixtures';

// The notes card on the home page: adding a note over HTMX, a refused one kept
// as typed, and the list's layout.
test.describe('notes', { tag: ['@notes', '@home'] }, () => {
  test('adding a note appends it over HTMX (no reload) and resets the form', async ({ page }) => {
    await page.goto('/');
    const input = page.locator('.add-note input[name="body"]');
    const body = 'a note from the e2e run';
    await input.fill(body);
    await page.getByRole('button', { name: 'Add' }).click();
    // Newest first (afterbegin swap).
    await expect(page.locator('#note-list .note').first()).toContainText(body);
    await expect(input).toHaveValue(''); // ResetOnSuccess cleared it
  });

  test('a click right after adding a note is not lost to its swap (regression)', async ({ page }) => {
    // Swaps used to run inside a view transition, during which Chromium hit-tests
    // the whole page to <html>: a press released mid-swap never reached its
    // target. Only boosted navigation crossfades now. A real press straddles
    // the swap — locator.click() waits the transition out.
    await page.goto('/');
    const picker = page.locator('.picker');
    await picker.locator('summary').hover(); // aim now: hover() would wait out a transition too

    const added = page.waitForResponse((r) => r.url().endsWith('/notes') && r.request().method() === 'POST');
    await page.locator('.add-note input[name="body"]').fill('a note, then a click');
    await page.keyboard.press('Enter');
    await added;
    await page.mouse.down();
    await page.waitForTimeout(100); // a short, human press, released mid-swap
    await page.mouse.up();

    await expect(picker.locator('.picker-panel')).toBeVisible();
  });

  // A refused submit is a 422 routed by hx-status:422 into the form's error
  // slot; app.js resets the form only after a 2xx, so the input survives.
  test('a blank note is refused into the error slot and the input is kept', async ({ page }) => {
    await page.goto('/');
    const input = page.locator('.add-note input[name="body"]');
    await input.fill('   '); // passes `required`, trims to nothing on the server
    const submitted = page.waitForResponse((r) => r.url().endsWith('/notes'));
    await page.getByRole('button', { name: 'Add' }).click();
    expect((await submitted).status()).toBe(422);
    await expect(page.locator('#note-error')).toContainText('Write something first');
    await expect(input).toHaveValue('   ');
  });

  test('the list sits flush with the form, newest first', async ({ page }) => {
    await page.goto('/');
    const list = page.locator('#note-list');
    expect(await list.evaluate((el) => getComputedStyle(el).paddingLeft)).toBe('0px');
    // Among the seeded notes the welcome one is the newest, so it comes first.
    // (Other specs may have added newer notes above them on this worker's store.)
    const notes = await list.locator('.note-body').allTextContents();
    const at = (s: string) => notes.findIndex((n) => n.includes(s));
    expect(at('Welcome')).toBeGreaterThanOrEqual(0);
    expect(at('Welcome')).toBeLessThan(at('Notes live in a store'));
  });
});
