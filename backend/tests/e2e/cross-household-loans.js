import { chromium } from 'playwright';
import pg from 'pg';
import { createGroupsAndCategoriesViaUI } from './helpers/category-helpers.js';
const { Pool } = pg;

/**
 * Test Cross-Household Debt Visibility
 * 
 * Tests that a user linked as a contact in another household can see
 * shared debts in their Préstamos tab (read-only).
 * 
 * Flow:
 * 1. Register Jose, create household, add categories + payment method
 * 2. Register Maria, create her own household
 * 3. Jose adds Maria as a contact (link via DB)
 * 4. Jose creates a SPLIT movement involving Maria
 * 5. Maria opens Préstamos tab → sees cross-household debt with 🔗 badge
 * 6. Maria expands → sees source household name
 * 7. Maria's cross-household movements have NO edit/delete buttons
 * 8. Cleanup
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
  let mariaContactId = null;

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
    // STEP 3: Jose adds Maria as contact + link via DB
    // ==================================================================
    console.log('📝 Step 3: Jose adds Maria as linked contact...');

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

    // Link the contact to Maria's user account
    await pool.query(
      'UPDATE contacts SET linked_user_id = $1 WHERE id = $2',
      [mariaUserId, mariaContactId]
    );

    console.log('✅ Maria added as linked contact');

    // ==================================================================
    // STEP 4: Jose adds payment method
    // ==================================================================
    console.log('📝 Step 4: Adding payment method for Jose...');

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

    console.log('✅ Payment method added');

    // ==================================================================
    // STEP 5: Jose creates category groups and categories
    // ==================================================================
    console.log('📝 Step 5: Creating categories...');

    await createGroupsAndCategoriesViaUI(josePage, appUrl, [
      { name: 'Casa', icon: '🏠', categories: ['Gastos fijos'] }
    ]);

    console.log('✅ Categories created');

    // ==================================================================
    // STEP 6: Jose creates SPLIT movement with Maria
    // ==================================================================
    console.log('📝 Step 6: Jose creates SPLIT movement involving Maria...');

    await josePage.goto(`${appUrl}/registrar-movimiento`, { waitUntil: 'networkidle' });
    await josePage.waitForTimeout(2000);

    // Select SPLIT type
    await josePage.locator('button[data-tipo="SPLIT"]').click();
    await josePage.waitForTimeout(500);

    // Fill form
    await josePage.locator('#descripcion').fill('Arriendo mensual');
    await josePage.locator('#valor').fill('2000000');
    await josePage.selectOption('#categoria', 'Gastos fijos');
    await josePage.selectOption('#pagadorCompartido', 'Jose Test');
    await josePage.waitForTimeout(500);
    await josePage.selectOption('#metodo', 'Efectivo Jose');

    // Add Maria as participant
    await josePage.locator('#addParticipantBtn').click();
    await josePage.waitForTimeout(500);

    const participantSelects = await josePage.locator('#participantsList select').all();
    if (participantSelects.length >= 2) {
      await participantSelects[1].selectOption('Maria Isabel');
      await josePage.waitForTimeout(500);
    }

    // Equitable split (50/50) should be default
    const equitableChecked = await josePage.locator('#equitable').isChecked();
    if (!equitableChecked) {
      await josePage.locator('#equitable').check();
      await josePage.waitForTimeout(300);
    }

    // Submit
    await submitFormAndConfirm(josePage);
    await josePage.waitForURL('**/', { timeout: 5000 });
    await josePage.waitForTimeout(1000);

    console.log('✅ SPLIT movement created (Jose pays $2M, Maria 50%)');

    // ==================================================================
    // STEP 7: Maria navigates to Préstamos tab
    // ==================================================================
    console.log('📝 Step 7: Maria opens Préstamos tab...');

    await mariaPage.goto(appUrl);
    await mariaPage.waitForTimeout(2000);

    // Click Préstamos tab
    await mariaPage.locator('button[data-tab="prestamos"]').click();
    await mariaPage.waitForTimeout(3000);

    console.log('✅ Maria is on Préstamos tab');

    // ==================================================================
    // STEP 8: Verify cross-household debt card is visible
    // ==================================================================
    console.log('📝 Step 8: Verifying cross-household debt card...');

    // Maria should see a loan card
    const loanCards = await mariaPage.locator('.loan-card').count();
    if (loanCards === 0) {
      throw new Error('Maria should see at least one loan card but sees none');
    }
    console.log(`  Found ${loanCards} loan card(s)`);

    // Check for cross-household badge 🔗
    const crossBadge = await mariaPage.locator('.cross-household-badge').count();
    if (crossBadge === 0) {
      throw new Error('Expected 🔗 cross-household badge on debt card');
    }
    console.log('  ✓ Cross-household badge 🔗 is visible');

    // Verify it says "Maria Isabel debe a Jose Test" and shows amount
    const cardText = await mariaPage.locator('.loan-card').first().textContent();
    if (!cardText.includes('Maria Isabel') || !cardText.includes('Jose Test')) {
      throw new Error(`Expected card to mention Maria Isabel and Jose Test, got: ${cardText}`);
    }
    console.log('  ✓ Card shows correct debtor/creditor names');

    console.log('✅ Cross-household debt card verified');

    // ==================================================================
    // STEP 9: Expand card and verify Level 2 (direction breakdown)
    // ==================================================================
    console.log('📝 Step 9: Expanding debt card...');

    // Click the loan card to expand
    await mariaPage.locator('.loan-card').first().click();
    await mariaPage.waitForTimeout(1000);

    // Level 2 should show direction items
    const directionItems = await mariaPage.locator('.expense-category-item').count();
    if (directionItems === 0) {
      throw new Error('Expected direction items after expanding card');
    }
    console.log(`  Found ${directionItems} direction item(s)`);

    console.log('✅ Level 2 expanded');

    // ==================================================================
    // STEP 10: Expand to Level 3 and verify movements
    // ==================================================================
    console.log('📝 Step 10: Expanding to Level 3 (movements)...');

    // Click the first direction item to see movements
    await mariaPage.locator('.expense-category-item').first().click();
    await mariaPage.waitForTimeout(1000);

    // Should see movement entries
    const movementEntries = await mariaPage.locator('.movement-detail-entry').count();
    if (movementEntries === 0) {
      throw new Error('Expected movement entries at Level 3');
    }
    console.log(`  Found ${movementEntries} movement(s)`);

    // Verify source household name is shown
    const sourceLabel = await mariaPage.locator('.cross-household-source').count();
    if (sourceLabel === 0) {
      throw new Error('Expected source household label (🔗 Hogar Jose...)');
    }
    const sourceLabelText = await mariaPage.locator('.cross-household-source').first().textContent();
    console.log(`  ✓ Source household shown: "${sourceLabelText}"`);

    // Verify cross-household entry has purple left border
    const crossEntry = await mariaPage.locator('.cross-household-entry').count();
    if (crossEntry === 0) {
      throw new Error('Expected .cross-household-entry styling on movement');
    }
    console.log('  ✓ Cross-household entry styling applied');

    console.log('✅ Level 3 movements verified');

    // ==================================================================
    // STEP 11: Verify NO edit/delete for cross-household movements
    // ==================================================================
    console.log('📝 Step 11: Verifying read-only (no edit/delete)...');

    // Cross-household entries should NOT have three-dots buttons
    const threeDotsBtns = await mariaPage.locator('.cross-household-entry .three-dots-btn').count();
    if (threeDotsBtns > 0) {
      throw new Error('Cross-household movements should NOT have edit/delete buttons');
    }
    console.log('  ✓ No edit/delete buttons on cross-household movements');

    console.log('✅ Read-only verified');

    // ==================================================================
    // STEP 12: Verify Jose's Préstamos is unchanged
    // ==================================================================
    console.log('📝 Step 12: Verifying Jose\'s Préstamos is unchanged...');

    await josePage.goto(appUrl);
    await josePage.waitForTimeout(2000);

    await josePage.locator('button[data-tab="prestamos"]').click();
    await josePage.waitForTimeout(3000);

    // Jose should see loan cards too (his own household view)
    const joseCards = await josePage.locator('.loan-card').count();
    if (joseCards === 0) {
      throw new Error('Jose should see loan cards in his Préstamos tab');
    }

    // Jose should NOT see cross-household badges (debts are in his household)
    const joseCrossBadge = await josePage.locator('.cross-household-badge').count();
    if (joseCrossBadge > 0) {
      throw new Error('Jose should NOT see cross-household badges (debts are local)');
    }
    console.log('  ✓ Jose sees debts without cross-household badge');

    // Jose should have edit/delete buttons on his movements
    await josePage.locator('.loan-card').first().click();
    await josePage.waitForTimeout(1000);
    await josePage.locator('.expense-category-item').first().click();
    await josePage.waitForTimeout(1000);

    const joseThreeDots = await josePage.locator('.movement-detail-entry .three-dots-btn').count();
    if (joseThreeDots === 0) {
      throw new Error('Jose should have edit/delete buttons on his own movements');
    }
    console.log('  ✓ Jose has edit/delete buttons on his movements');

    console.log('✅ Jose\'s view unchanged');

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
    await pool.query('DELETE FROM household_members WHERE household_id = $1', [mariaHouseholdId]);
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
        await pool.query('DELETE FROM household_members WHERE household_id = $1', [mariaHouseholdId]);
        await pool.query('DELETE FROM households WHERE id = $1', [mariaHouseholdId]);
      }
      if (joseUserId) {
        await pool.query('DELETE FROM payment_methods WHERE owner_id = $1', [joseUserId]);
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
