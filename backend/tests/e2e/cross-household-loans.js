import { chromium } from 'playwright';
import pg from 'pg';
import { createGroupsAndCategoriesViaUI } from './helpers/category-helpers.js';
const { Pool } = pg;

/**
 * Test Cross-Household Debt Visibility
 * 
 * Tests that:
 * 1. A user linked as a contact in another household can see shared debts (read-only)
 * 2. Debts from cross-household and own-household NET correctly (consolidation)
 * 3. Each household shows names as stored locally (contact names, not foreign names)
 * 
 * Flow:
 * 1. Register Jose, create household, add categories + payment method
 * 2. Register Maria, create her own household with categories + payment method
 * 3. Jose adds Maria as contact (link via DB); Maria adds Jose as contact (link via DB)
 * 4. Jose creates SPLIT $2M (Maria 50%) → Maria owes Jose $1M
 * 5. Maria creates SPLIT $600K (Jose 50%) → Jose owes Maria $300K
 * 6. Jose views Préstamos: ONE card showing Maria owes $700K (netted: $1M - $300K)
 * 7. Maria views Préstamos: ONE card showing she owes $700K, with 🔗 badge on cross-household movement
 * 8. Names verified: Jose sees "Maria Isabel" (his contact), Maria sees "Josecito" (her contact)
 * 9. Cross-household movements have NO edit/delete buttons
 * 10. Cleanup
 */

async function submitFormAndConfirm(page) {
  await page.locator('#submitBtn').click();
  await page.waitForSelector('.modal-overlay', { timeout: 5000 });
  await page.locator('#modal-ok').click();
  await page.waitForSelector('.modal-overlay', { state: 'detached', timeout: 5000 });
}

async function testCrossHouseholdLoans() {
  const headless = process.env.CI === 'true' || process.env.HEADLESS === 'true';
  const appUrl = process.env.APP_URL || 'http://localhost:8080';
  const dbUrl = process.env.DATABASE_URL || 'postgres://conti:conti_dev_password@localhost:5432/conti?sslmode=disable';

  const browser = await chromium.launch({ headless });
  const pool = new Pool({ connectionString: dbUrl });

  const timestamp = Date.now();
  const joseEmail = `jose-cross-${timestamp}@example.com`;
  const mariaEmail = `maria-cross-${timestamp}@example.com`;
  const password = 'TestPassword123!';
  const joseHouseholdName = `Hogar Jose ${timestamp}`;
  const mariaHouseholdName = `Hogar Maria ${timestamp}`;

  let joseUserId = null;
  let mariaUserId = null;
  let joseHouseholdId = null;
  let mariaHouseholdId = null;
  let mariaContactId = null;  // Maria as contact in Jose's household
  let joseContactId = null;   // Jose as contact in Maria's household

  let josePage = null;
  let mariaPage = null;

  try {
    console.log('🚀 Starting Cross-Household Debt Visibility E2E Test');
    console.log('👤 Jose:', joseEmail);
    console.log('👩 Maria:', mariaEmail);
    console.log('');

    // ==================================================================
    // STEP 1: Register Jose + create household
    // ==================================================================
    console.log('📝 Step 1: Registering Jose and creating household...');

    const joseContext = await browser.newContext();
    josePage = await joseContext.newPage();

    await josePage.goto(appUrl);
    await josePage.waitForTimeout(1000);

    await josePage.getByRole('link', { name: 'Regístrate' }).click();
    await josePage.waitForTimeout(500);

    await josePage.locator('#registerName').fill('Jose Test');
    await josePage.locator('#registerEmail').fill(joseEmail);
    await josePage.locator('#registerPassword').fill(password);
    await josePage.locator('#registerConfirm').fill(password);
    await josePage.getByRole('button', { name: 'Registrarse' }).click();
    await josePage.waitForTimeout(2000);

    const joseResult = await pool.query('SELECT id FROM users WHERE email = $1', [joseEmail]);
    joseUserId = joseResult.rows[0].id;

    // Create household
    await josePage.locator('#hamburger-btn').click();
    await josePage.waitForTimeout(500);
    await josePage.getByRole('link', { name: 'Perfil' }).click();
    await josePage.waitForTimeout(1000);

    await josePage.getByRole('button', { name: 'Crear hogar' }).click();
    await josePage.waitForTimeout(500);
    await josePage.locator('#household-name-input').fill(joseHouseholdName);
    await josePage.locator('#household-create-btn').click();
    await josePage.waitForTimeout(1000);
    await josePage.locator('#modal-ok').click();
    await josePage.waitForTimeout(2000);

    const joseHH = await pool.query('SELECT id FROM households WHERE name = $1', [joseHouseholdName]);
    joseHouseholdId = joseHH.rows[0].id;

    console.log('✅ Jose registered, household created');

    // ==================================================================
    // STEP 2: Register Maria + create household
    // ==================================================================
    console.log('📝 Step 2: Registering Maria and creating household...');

    const mariaContext = await browser.newContext();
    mariaPage = await mariaContext.newPage();

    await mariaPage.goto(appUrl);
    await mariaPage.waitForTimeout(1000);

    await mariaPage.getByRole('link', { name: 'Regístrate' }).click();
    await mariaPage.waitForTimeout(500);

    await mariaPage.locator('#registerName').fill('Maria Isabel');
    await mariaPage.locator('#registerEmail').fill(mariaEmail);
    await mariaPage.locator('#registerPassword').fill(password);
    await mariaPage.locator('#registerConfirm').fill(password);
    await mariaPage.getByRole('button', { name: 'Registrarse' }).click();
    await mariaPage.waitForTimeout(2000);

    const mariaResult = await pool.query('SELECT id FROM users WHERE email = $1', [mariaEmail]);
    mariaUserId = mariaResult.rows[0].id;

    // Create Maria's household
    await mariaPage.locator('#hamburger-btn').click();
    await mariaPage.waitForTimeout(500);
    await mariaPage.getByRole('link', { name: 'Perfil' }).click();
    await mariaPage.waitForTimeout(1000);

    await mariaPage.getByRole('button', { name: 'Crear hogar' }).click();
    await mariaPage.waitForTimeout(500);
    await mariaPage.locator('#household-name-input').fill(mariaHouseholdName);
    await mariaPage.locator('#household-create-btn').click();
    await mariaPage.waitForTimeout(1000);
    await mariaPage.locator('#modal-ok').click();
    await mariaPage.waitForTimeout(2000);

    const mariaHH = await pool.query('SELECT id FROM households WHERE name = $1', [mariaHouseholdName]);
    mariaHouseholdId = mariaHH.rows[0].id;

    console.log('✅ Maria registered, household created');

    // ==================================================================
    // STEP 3: Jose adds Maria as contact + Maria adds Jose as contact
    // ==================================================================
    console.log('📝 Step 3: Adding linked contacts...');

    // Jose adds "Maria Isabel" as contact
    await josePage.goto(`${appUrl}/hogar`);
    await josePage.waitForTimeout(2000);

    await josePage.getByRole('button', { name: '+ Agregar contacto' }).click();
    await josePage.waitForTimeout(500);

    await josePage.locator('#contact-name').fill('Maria Isabel');
    await josePage.locator('#contact-email').fill(mariaEmail);
    await josePage.getByRole('button', { name: 'Agregar', exact: true }).click();
    await josePage.waitForTimeout(3000);

    const contactResult = await pool.query(
      'SELECT id FROM contacts WHERE household_id = $1 AND name = $2',
      [joseHouseholdId, 'Maria Isabel']
    );
    mariaContactId = contactResult.rows[0].id;

    // Link to Maria's user account
    await pool.query(
      'UPDATE contacts SET linked_user_id = $1 WHERE id = $2',
      [mariaUserId, mariaContactId]
    );

    // Maria adds "Josecito" as contact (different name for the same person!)
    await mariaPage.goto(`${appUrl}/hogar`);
    await mariaPage.waitForTimeout(2000);

    await mariaPage.getByRole('button', { name: '+ Agregar contacto' }).click();
    await mariaPage.waitForTimeout(500);

    await mariaPage.locator('#contact-name').fill('Josecito');
    await mariaPage.locator('#contact-email').fill(joseEmail);
    await mariaPage.getByRole('button', { name: 'Agregar', exact: true }).click();
    await mariaPage.waitForTimeout(3000);

    const joseContactResult = await pool.query(
      'SELECT id FROM contacts WHERE household_id = $1 AND name = $2',
      [mariaHouseholdId, 'Josecito']
    );
    joseContactId = joseContactResult.rows[0].id;

    // Link to Jose's user account
    await pool.query(
      'UPDATE contacts SET linked_user_id = $1 WHERE id = $2',
      [joseUserId, joseContactId]
    );

    console.log('✅ Linked contacts created (Jose→"Maria Isabel", Maria→"Josecito")');

    // ==================================================================
    // STEP 4: Jose adds payment method + categories
    // ==================================================================
    console.log('📝 Step 4: Adding payment method and categories for Jose...');

    await josePage.goto(`${appUrl}/perfil`);
    await josePage.waitForTimeout(2000);

    await josePage.locator('#add-payment-method-btn').waitFor({ state: 'visible', timeout: 10000 });
    await josePage.locator('#add-payment-method-btn').click();
    await josePage.waitForTimeout(500);

    await josePage.locator('#pm-name').fill('Efectivo Jose');
    await josePage.selectOption('select#pm-type', 'cash');

    const isSharedCheckbox = josePage.locator('#pm-shared');
    if (await isSharedCheckbox.isChecked()) {
      await isSharedCheckbox.uncheck();
    }

    await josePage.getByRole('button', { name: 'Agregar', exact: true }).click();
    await josePage.waitForTimeout(1500);
    await josePage.keyboard.press('Escape');
    await josePage.waitForTimeout(500);

    await createGroupsAndCategoriesViaUI(josePage, appUrl, [
      { name: 'Casa', icon: '🏠', categories: ['Gastos fijos'] }
    ]);

    console.log('✅ Jose payment method + categories created');

    // ==================================================================
    // STEP 5: Maria adds payment method + categories
    // ==================================================================
    console.log('📝 Step 5: Adding payment method and categories for Maria...');

    await mariaPage.goto(`${appUrl}/perfil`);
    await mariaPage.waitForTimeout(2000);

    await mariaPage.locator('#add-payment-method-btn').waitFor({ state: 'visible', timeout: 10000 });
    await mariaPage.locator('#add-payment-method-btn').click();
    await mariaPage.waitForTimeout(500);

    await mariaPage.locator('#pm-name').fill('Efectivo Maria');
    await mariaPage.selectOption('select#pm-type', 'cash');

    const mariaSharedCheckbox = mariaPage.locator('#pm-shared');
    if (await mariaSharedCheckbox.isChecked()) {
      await mariaSharedCheckbox.uncheck();
    }

    await mariaPage.getByRole('button', { name: 'Agregar', exact: true }).click();
    await mariaPage.waitForTimeout(1500);
    await mariaPage.keyboard.press('Escape');
    await mariaPage.waitForTimeout(500);

    await createGroupsAndCategoriesViaUI(mariaPage, appUrl, [
      { name: 'Compartidos', icon: '🎁', categories: ['Salidas'] }
    ]);

    console.log('✅ Maria payment method + categories created');

    // ==================================================================
    // STEP 6: Jose creates SPLIT $2M (Maria 50% → Maria owes Jose $1M)
    // ==================================================================
    console.log('📝 Step 6: Jose creates SPLIT $2M with Maria 50%...');

    await josePage.goto(`${appUrl}/registrar-movimiento`, { waitUntil: 'networkidle' });
    await josePage.waitForTimeout(2000);

    await josePage.locator('button[data-tipo="SPLIT"]').click();
    await josePage.waitForTimeout(500);

    await josePage.locator('#descripcion').fill('Arriendo mensual');
    await josePage.locator('#valor').fill('2000000');
    await josePage.selectOption('#categoria', 'Gastos fijos');
    await josePage.selectOption('#pagadorCompartido', 'Jose Test');
    await josePage.waitForTimeout(500);
    await josePage.selectOption('#metodo', 'Efectivo Jose');

    // Add Maria as participant
    await josePage.locator('#addParticipantBtn').click();
    await josePage.waitForTimeout(500);

    const joseParticipantSelects = await josePage.locator('#participantsList select').all();
    if (joseParticipantSelects.length >= 2) {
      await joseParticipantSelects[1].selectOption('Maria Isabel');
      await josePage.waitForTimeout(500);
    }

    const equitableChecked = await josePage.locator('#equitable').isChecked();
    if (!equitableChecked) {
      await josePage.locator('#equitable').check();
      await josePage.waitForTimeout(300);
    }

    await submitFormAndConfirm(josePage);
    await josePage.waitForURL('**/', { timeout: 5000 });
    await josePage.waitForTimeout(1000);

    console.log('✅ Jose SPLIT created: Maria owes Jose $1,000,000');

    // ==================================================================
    // STEP 7: Maria creates SPLIT $600K (Josecito 50% → Jose owes Maria $300K)
    // ==================================================================
    console.log('📝 Step 7: Maria creates SPLIT $600K with Josecito 50%...');

    await mariaPage.goto(`${appUrl}/registrar-movimiento`, { waitUntil: 'networkidle' });
    await mariaPage.waitForTimeout(2000);

    await mariaPage.locator('button[data-tipo="SPLIT"]').click();
    await mariaPage.waitForTimeout(500);

    await mariaPage.locator('#descripcion').fill('Cena en restaurante');
    await mariaPage.locator('#valor').fill('600000');
    await mariaPage.selectOption('#categoria', 'Salidas');
    await mariaPage.selectOption('#pagadorCompartido', 'Maria Isabel');
    await mariaPage.waitForTimeout(500);
    await mariaPage.selectOption('#metodo', 'Efectivo Maria');

    // Add Josecito as participant
    await mariaPage.locator('#addParticipantBtn').click();
    await mariaPage.waitForTimeout(500);

    const mariaParticipantSelects = await mariaPage.locator('#participantsList select').all();
    if (mariaParticipantSelects.length >= 2) {
      await mariaParticipantSelects[1].selectOption('Josecito');
      await mariaPage.waitForTimeout(500);
    }

    const mariaEquitableChecked = await mariaPage.locator('#equitable').isChecked();
    if (!mariaEquitableChecked) {
      await mariaPage.locator('#equitable').check();
      await mariaPage.waitForTimeout(300);
    }

    await submitFormAndConfirm(mariaPage);
    await mariaPage.waitForURL('**/', { timeout: 5000 });
    await mariaPage.waitForTimeout(1000);

    console.log('✅ Maria SPLIT created: Jose owes Maria $300,000');

    // ==================================================================
    // STEP 8: Jose views Préstamos — should see ONE netted card
    // ==================================================================
    console.log('📝 Step 8: Jose views Préstamos (expecting netted debts)...');

    await josePage.goto(appUrl);
    await josePage.waitForTimeout(2000);

    await josePage.locator('button[data-tab="prestamos"]').click();
    await josePage.waitForTimeout(3000);

    // Should see exactly ONE loan card (netted)
    const joseCards = await josePage.locator('.loan-card').count();
    if (joseCards !== 1) {
      // Debug: print card contents
      for (let i = 0; i < joseCards; i++) {
        const txt = await josePage.locator('.loan-card').nth(i).textContent();
        console.log(`  Card ${i}: ${txt}`);
      }
      throw new Error(`Jose should see exactly 1 netted loan card, but sees ${joseCards}`);
    }
    console.log('  ✓ Jose sees exactly 1 netted loan card');

    // Verify card says "Maria Isabel" (Jose's contact name) 
    const joseCardText = await josePage.locator('.loan-card').first().textContent();
    if (!joseCardText.includes('Maria Isabel')) {
      throw new Error(`Jose should see "Maria Isabel" (his contact name), got: ${joseCardText}`);
    }
    console.log('  ✓ Card shows "Maria Isabel" (Jose\'s local contact name)');

    // Verify netted amount: $1M - $300K = $700K
    if (!joseCardText.includes('700')) {
      throw new Error(`Expected netted amount of ~$700,000 in card, got: ${joseCardText}`);
    }
    console.log('  ✓ Card shows netted amount (~$700,000)');

    // The direction should be: "Maria Isabel debe a Jose Test"
    if (!joseCardText.includes('debe')) {
      throw new Error(`Expected "debe" in card text, got: ${joseCardText}`);
    }
    console.log('  ✓ Card shows correct debt direction');

    console.log('✅ Jose Préstamos: netting verified');

    // ==================================================================
    // STEP 9: Jose expands and has edit/delete on own movements
    // ==================================================================
    console.log('📝 Step 9: Verifying Jose can edit/delete own movements...');

    await josePage.locator('.loan-card').first().click();
    await josePage.waitForTimeout(1000);

    await josePage.locator('.expense-category-item').first().click();
    await josePage.waitForTimeout(1000);

    // Jose should see his own movement with three-dots
    const joseMovements = await josePage.locator('.movement-detail-entry').count();
    if (joseMovements === 0) {
      throw new Error('Jose should see movement entries');
    }

    // At least some movements should have visible three-dots (own movements)
    const joseVisibleDots = await josePage.locator('.movement-detail-entry .three-dots-btn:not([style*="visibility: hidden"])').count();
    if (joseVisibleDots === 0) {
      throw new Error('Jose should have edit/delete on his own movements');
    }
    console.log(`  ✓ Jose has ${joseVisibleDots} editable movement(s)`);

    console.log('✅ Jose edit/delete verified');

    // ==================================================================
    // STEP 10: Maria views Préstamos — should see ONE netted card
    // ==================================================================
    console.log('📝 Step 10: Maria views Préstamos (expecting netted debts)...');

    await mariaPage.goto(appUrl);
    await mariaPage.waitForTimeout(2000);

    await mariaPage.locator('button[data-tab="prestamos"]').click();
    await mariaPage.waitForTimeout(3000);

    // Should see exactly ONE loan card (netted)
    const mariaCards = await mariaPage.locator('.loan-card').count();
    if (mariaCards !== 1) {
      for (let i = 0; i < mariaCards; i++) {
        const txt = await mariaPage.locator('.loan-card').nth(i).textContent();
        console.log(`  Card ${i}: ${txt}`);
      }
      throw new Error(`Maria should see exactly 1 netted loan card, but sees ${mariaCards}`);
    }
    console.log('  ✓ Maria sees exactly 1 netted loan card');

    // Verify card says "Josecito" (Maria's contact name for Jose)
    const mariaCardText = await mariaPage.locator('.loan-card').first().textContent();
    if (!mariaCardText.includes('Josecito')) {
      throw new Error(`Maria should see "Josecito" (her contact name for Jose), got: ${mariaCardText}`);
    }
    console.log('  ✓ Card shows "Josecito" (Maria\'s local contact name)');

    // Verify netted amount: $1M - $300K = $700K
    if (!mariaCardText.includes('700')) {
      throw new Error(`Expected netted amount of ~$700,000 in Maria's card, got: ${mariaCardText}`);
    }
    console.log('  ✓ Card shows netted amount (~$700,000)');

    console.log('✅ Maria Préstamos: netting and local names verified');

    // ==================================================================
    // STEP 11: Maria expands to Level 3 — verify badges and read-only
    // ==================================================================
    console.log('📝 Step 11: Maria expands to Level 3...');

    await mariaPage.locator('.loan-card').first().click();
    await mariaPage.waitForTimeout(1000);

    // Expand ALL direction items to see all movements
    const directionItems = await mariaPage.locator('.expense-category-item').count();
    for (let i = 0; i < directionItems; i++) {
      await mariaPage.locator('.expense-category-item').nth(i).click();
      await mariaPage.waitForTimeout(500);
    }
    await mariaPage.waitForTimeout(500);

    const movementEntries = await mariaPage.locator('.movement-detail-entry').count();
    if (movementEntries === 0) {
      throw new Error('Maria should see movement entries at Level 3');
    }
    console.log(`  ✓ Found ${movementEntries} movement(s) across ${directionItems} direction(s)`);

    // Verify 🔗 cross-household badge on cross-household movement
    const crossBadges = await mariaPage.locator('.entry-cross-household-badge').count();
    if (crossBadges === 0) {
      throw new Error('Expected 🔗 badge on cross-household movement');
    }
    const badgeText = await mariaPage.locator('.entry-cross-household-badge').first().textContent();
    console.log(`  ✓ Cross-household badge shown: "${badgeText.trim()}"`);

    // Cross-household entries should NOT have visible three-dots
    const crossEntryDots = await mariaPage.locator('.cross-household-entry .three-dots-btn:not([style*="visibility: hidden"])').count();
    if (crossEntryDots > 0) {
      throw new Error('Cross-household movements should NOT have visible edit/delete buttons');
    }
    console.log('  ✓ Cross-household movements are read-only (no edit/delete)');

    // Maria's own movement SHOULD have edit/delete
    const ownMovementDots = await mariaPage.locator('.movement-detail-entry:not(.cross-household-entry) .three-dots-btn').count();
    if (ownMovementDots === 0) {
      throw new Error('Maria should have edit/delete on her own movements');
    }
    console.log(`  ✓ Maria has edit/delete on her own movement(s)`);

    console.log('✅ Level 3 badges and read-only verified');

    // ==================================================================
    // CLEANUP
    // ==================================================================
    console.log('');
    console.log('🧹 Cleaning up test data...');

    // Jose's household
    await pool.query('DELETE FROM movement_participants WHERE movement_id IN (SELECT id FROM movements WHERE household_id = $1)', [joseHouseholdId]);
    await pool.query('DELETE FROM movements WHERE household_id = $1', [joseHouseholdId]);
    await pool.query('DELETE FROM monthly_budgets WHERE category_id IN (SELECT id FROM categories WHERE household_id = $1)', [joseHouseholdId]);
    await pool.query('DELETE FROM categories WHERE household_id = $1', [joseHouseholdId]);
    await pool.query('DELETE FROM category_groups WHERE household_id = $1', [joseHouseholdId]);
    await pool.query('DELETE FROM contacts WHERE household_id = $1', [joseHouseholdId]);
    await pool.query('DELETE FROM household_members WHERE household_id = $1', [joseHouseholdId]);
    await pool.query('DELETE FROM payment_methods WHERE owner_id = $1', [joseUserId]);
    await pool.query('DELETE FROM households WHERE id = $1', [joseHouseholdId]);

    // Maria's household
    await pool.query('DELETE FROM movement_participants WHERE movement_id IN (SELECT id FROM movements WHERE household_id = $1)', [mariaHouseholdId]);
    await pool.query('DELETE FROM movements WHERE household_id = $1', [mariaHouseholdId]);
    await pool.query('DELETE FROM monthly_budgets WHERE category_id IN (SELECT id FROM categories WHERE household_id = $1)', [mariaHouseholdId]);
    await pool.query('DELETE FROM categories WHERE household_id = $1', [mariaHouseholdId]);
    await pool.query('DELETE FROM category_groups WHERE household_id = $1', [mariaHouseholdId]);
    await pool.query('DELETE FROM contacts WHERE household_id = $1', [mariaHouseholdId]);
    await pool.query('DELETE FROM household_members WHERE household_id = $1', [mariaHouseholdId]);
    await pool.query('DELETE FROM payment_methods WHERE owner_id = $1', [mariaUserId]);
    await pool.query('DELETE FROM households WHERE id = $1', [mariaHouseholdId]);

    // Users
    await pool.query('DELETE FROM sessions WHERE user_id IN ($1, $2)', [joseUserId, mariaUserId]);
    await pool.query('DELETE FROM users WHERE id IN ($1, $2)', [joseUserId, mariaUserId]);

    console.log('✅ Cleanup complete');
    console.log('');
    console.log('✅ ✅ ✅ ALL CROSS-HOUSEHOLD DEBT VISIBILITY TESTS PASSED! ✅ ✅ ✅');

    await browser.close();
    await pool.end();

  } catch (error) {
    console.error('❌ Test failed:', error.message);

    // Save screenshots on failure
    try {
      if (mariaPage) {
        const mariaScreenshot = process.env.CI
          ? 'test-results/cross-household-maria-failure.png'
          : '/tmp/cross-household-maria-failure.png';
        await mariaPage.screenshot({ path: mariaScreenshot, fullPage: true });
        console.log('📸 Maria screenshot:', mariaScreenshot);
      }
      if (josePage) {
        const joseScreenshot = process.env.CI
          ? 'test-results/cross-household-jose-failure.png'
          : '/tmp/cross-household-jose-failure.png';
        await josePage.screenshot({ path: joseScreenshot, fullPage: true });
        console.log('📸 Jose screenshot:', joseScreenshot);
      }
    } catch (screenshotError) {
      console.error('Failed to save screenshots:', screenshotError);
    }

    // Cleanup on failure
    try {
      if (joseHouseholdId) {
        await pool.query('DELETE FROM movement_participants WHERE movement_id IN (SELECT id FROM movements WHERE household_id = $1)', [joseHouseholdId]);
        await pool.query('DELETE FROM movements WHERE household_id = $1', [joseHouseholdId]);
        await pool.query('DELETE FROM monthly_budgets WHERE category_id IN (SELECT id FROM categories WHERE household_id = $1)', [joseHouseholdId]);
        await pool.query('DELETE FROM categories WHERE household_id = $1', [joseHouseholdId]);
        await pool.query('DELETE FROM category_groups WHERE household_id = $1', [joseHouseholdId]);
        await pool.query('DELETE FROM contacts WHERE household_id = $1', [joseHouseholdId]);
        await pool.query('DELETE FROM household_members WHERE household_id = $1', [joseHouseholdId]);
      }
      if (mariaHouseholdId) {
        await pool.query('DELETE FROM movement_participants WHERE movement_id IN (SELECT id FROM movements WHERE household_id = $1)', [mariaHouseholdId]);
        await pool.query('DELETE FROM movements WHERE household_id = $1', [mariaHouseholdId]);
        await pool.query('DELETE FROM monthly_budgets WHERE category_id IN (SELECT id FROM categories WHERE household_id = $1)', [mariaHouseholdId]);
        await pool.query('DELETE FROM categories WHERE household_id = $1', [mariaHouseholdId]);
        await pool.query('DELETE FROM category_groups WHERE household_id = $1', [mariaHouseholdId]);
        await pool.query('DELETE FROM contacts WHERE household_id = $1', [mariaHouseholdId]);
        await pool.query('DELETE FROM household_members WHERE household_id = $1', [mariaHouseholdId]);
        await pool.query('DELETE FROM households WHERE id = $1', [mariaHouseholdId]);
      }
      if (joseUserId) {
        await pool.query('DELETE FROM payment_methods WHERE owner_id = $1', [joseUserId]);
      }
      if (mariaUserId) {
        await pool.query('DELETE FROM payment_methods WHERE owner_id = $1', [mariaUserId]);
      }
      if (joseHouseholdId) {
        await pool.query('DELETE FROM households WHERE id = $1', [joseHouseholdId]);
      }
      if (joseUserId || mariaUserId) {
        await pool.query('DELETE FROM sessions WHERE user_id IN ($1, $2)', [joseUserId || '00000000-0000-0000-0000-000000000000', mariaUserId || '00000000-0000-0000-0000-000000000000']);
        if (joseUserId) await pool.query('DELETE FROM users WHERE id = $1', [joseUserId]);
        if (mariaUserId) await pool.query('DELETE FROM users WHERE id = $1', [mariaUserId]);
      }
    } catch (cleanupError) {
      console.error('Cleanup failed:', cleanupError);
    }

    await browser.close();
    await pool.end();
    throw error;
  }
}

testCrossHouseholdLoans();
