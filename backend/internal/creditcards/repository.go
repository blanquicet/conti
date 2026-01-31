package creditcards

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Repository handles database operations for credit card summaries
type Repository interface {
	GetCreditCards(ctx context.Context, householdID string) ([]*CardSummary, error)
	GetCardCharges(ctx context.Context, cardID string, startDate, endDate time.Time) ([]*CardMovement, float64, error)
	GetCardPayments(ctx context.Context, cardID string, startDate, endDate time.Time) ([]*CardPayment, float64, error)
	GetSavingsBalances(ctx context.Context, householdID string, asOfDate time.Time) ([]*AccountBalance, error)
}

type repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a new credit cards repository
func NewRepository(pool *pgxpool.Pool) Repository {
	return &repository{pool: pool}
}

// GetCreditCards returns all credit cards for a household
func (r *repository) GetCreditCards(ctx context.Context, householdID string) ([]*CardSummary, error) {
	query := `
		SELECT 
			pm.id,
			pm.name,
			pm.owner_id,
			u.name as owner_name,
			pm.cutoff_day,
			pm.institution,
			pm.last4
		FROM payment_methods pm
		JOIN users u ON pm.owner_id = u.id
		WHERE pm.household_id = $1
			AND pm.type = 'credit_card'
			AND pm.is_active = true
		ORDER BY u.name, pm.name
	`

	rows, err := r.pool.Query(ctx, query, householdID)
	if err != nil {
		return nil, fmt.Errorf("query credit cards: %w", err)
	}
	defer rows.Close()

	var cards []*CardSummary
	for rows.Next() {
		card := &CardSummary{}
		err := rows.Scan(
			&card.ID,
			&card.Name,
			&card.OwnerID,
			&card.OwnerName,
			&card.CutoffDay,
			&card.Institution,
			&card.Last4,
		)
		if err != nil {
			return nil, fmt.Errorf("scan credit card: %w", err)
		}
		cards = append(cards, card)
	}

	return cards, nil
}

// GetCardCharges returns all movements charged to a credit card in a date range
func (r *repository) GetCardCharges(ctx context.Context, cardID string, startDate, endDate time.Time) ([]*CardMovement, float64, error) {
	query := `
		SELECT 
			m.id,
			m.type,
			m.description,
			m.amount,
			m.movement_date,
			c.name as category_name,
			COALESCE(u.name, ct.name, 'Unknown') as payer_name
		FROM movements m
		LEFT JOIN categories c ON m.category_id = c.id
		LEFT JOIN users u ON m.payer_user_id = u.id
		LEFT JOIN contacts ct ON m.payer_contact_id = ct.id
		WHERE m.payment_method_id = $1
			AND m.movement_date >= $2
			AND m.movement_date < $3
		ORDER BY m.movement_date DESC
	`

	rows, err := r.pool.Query(ctx, query, cardID, startDate, endDate)
	if err != nil {
		return nil, 0, fmt.Errorf("query card charges: %w", err)
	}
	defer rows.Close()

	var movements []*CardMovement
	var total float64
	for rows.Next() {
		m := &CardMovement{}
		err := rows.Scan(
			&m.ID,
			&m.Type,
			&m.Description,
			&m.Amount,
			&m.MovementDate,
			&m.CategoryName,
			&m.PayerName,
		)
		if err != nil {
			return nil, 0, fmt.Errorf("scan card movement: %w", err)
		}
		movements = append(movements, m)
		total += m.Amount
	}

	return movements, total, nil
}

// GetCardPayments returns all payments made to a credit card in a date range
func (r *repository) GetCardPayments(ctx context.Context, cardID string, startDate, endDate time.Time) ([]*CardPayment, float64, error) {
	query := `
		SELECT 
			ccp.id,
			ccp.amount,
			ccp.payment_date,
			a.name as source_account_name,
			ccp.notes
		FROM credit_card_payments ccp
		JOIN accounts a ON ccp.source_account_id = a.id
		WHERE ccp.credit_card_id = $1
			AND ccp.payment_date >= $2
			AND ccp.payment_date < $3
		ORDER BY ccp.payment_date DESC
	`

	rows, err := r.pool.Query(ctx, query, cardID, startDate, endDate)
	if err != nil {
		return nil, 0, fmt.Errorf("query card payments: %w", err)
	}
	defer rows.Close()

	var payments []*CardPayment
	var total float64
	for rows.Next() {
		p := &CardPayment{}
		err := rows.Scan(
			&p.ID,
			&p.Amount,
			&p.PaymentDate,
			&p.SourceAccountName,
			&p.Notes,
		)
		if err != nil {
			return nil, 0, fmt.Errorf("scan card payment: %w", err)
		}
		payments = append(payments, p)
		total += p.Amount
	}

	return payments, total, nil
}

// GetSavingsBalances calculates balances for all savings and cash accounts
// Balance = initial_balance + income - debit_spending - card_payments
func (r *repository) GetSavingsBalances(ctx context.Context, householdID string, asOfDate time.Time) ([]*AccountBalance, error) {
	query := `
		WITH account_income AS (
			SELECT 
				account_id,
				COALESCE(SUM(amount), 0) as total_income
			FROM income
			GROUP BY account_id
		),
		account_debit_spending AS (
			-- Movements paid by debit cards linked to each account
			SELECT 
				pm.linked_account_id as account_id,
				COALESCE(SUM(m.amount), 0) as total_spent
			FROM movements m
			JOIN payment_methods pm ON m.payment_method_id = pm.id
			WHERE pm.type = 'debit_card'
				AND pm.linked_account_id IS NOT NULL
			GROUP BY pm.linked_account_id
		),
		account_card_payments AS (
			-- Credit card payments from each account
			SELECT 
				source_account_id as account_id,
				COALESCE(SUM(amount), 0) as total_payments
			FROM credit_card_payments
			GROUP BY source_account_id
		),
		cash_spending AS (
			-- Movements paid with cash payment method
			SELECT 
				pm.linked_account_id as account_id,
				COALESCE(SUM(m.amount), 0) as total_spent
			FROM movements m
			JOIN payment_methods pm ON m.payment_method_id = pm.id
			WHERE pm.type = 'cash'
				AND pm.linked_account_id IS NOT NULL
			GROUP BY pm.linked_account_id
		)
		SELECT 
			a.id,
			a.name,
			a.type,
			COALESCE(a.initial_balance, 0) 
				+ COALESCE(ai.total_income, 0) 
				- COALESCE(ads.total_spent, 0) 
				- COALESCE(acp.total_payments, 0)
				- COALESCE(cs.total_spent, 0) as balance
		FROM accounts a
		LEFT JOIN account_income ai ON a.id = ai.account_id
		LEFT JOIN account_debit_spending ads ON a.id = ads.account_id
		LEFT JOIN account_card_payments acp ON a.id = acp.account_id
		LEFT JOIN cash_spending cs ON a.id = cs.account_id
		WHERE a.household_id = $1
			AND a.type IN ('savings', 'cash')
		ORDER BY a.name
	`

	rows, err := r.pool.Query(ctx, query, householdID)
	if err != nil {
		return nil, fmt.Errorf("query savings balances: %w", err)
	}
	defer rows.Close()

	var accounts []*AccountBalance
	for rows.Next() {
		acc := &AccountBalance{}
		err := rows.Scan(&acc.ID, &acc.Name, &acc.Type, &acc.Balance)
		if err != nil {
			return nil, fmt.Errorf("scan account balance: %w", err)
		}
		accounts = append(accounts, acc)
	}

	return accounts, nil
}
