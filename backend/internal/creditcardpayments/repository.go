package creditcardpayments

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// repository implements Repository using PostgreSQL
type repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a new credit card payment repository
func NewRepository(pool *pgxpool.Pool) Repository {
	return &repository{pool: pool}
}

// Create creates a new credit card payment
func (r *repository) Create(ctx context.Context, payment *CreditCardPayment) (*CreditCardPayment, error) {
	var result CreditCardPayment
	err := r.pool.QueryRow(ctx, `
		INSERT INTO credit_card_payments (
			household_id, credit_card_id, amount, payment_date, notes,
			source_account_id, created_by
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, household_id, credit_card_id, amount, payment_date, notes,
		          source_account_id, created_at, updated_at, created_by
	`, payment.HouseholdID, payment.CreditCardID, payment.Amount, payment.PaymentDate,
		payment.Notes, payment.SourceAccountID, payment.CreatedBy).Scan(
		&result.ID,
		&result.HouseholdID,
		&result.CreditCardID,
		&result.Amount,
		&result.PaymentDate,
		&result.Notes,
		&result.SourceAccountID,
		&result.CreatedAt,
		&result.UpdatedAt,
		&result.CreatedBy,
	)

	if err != nil {
		return nil, err
	}

	return &result, nil
}

// GetByID retrieves a credit card payment by ID
func (r *repository) GetByID(ctx context.Context, id string) (*CreditCardPayment, error) {
	var payment CreditCardPayment
	err := r.pool.QueryRow(ctx, `
		SELECT ccp.id, ccp.household_id, ccp.credit_card_id, ccp.amount,
		       ccp.payment_date, ccp.notes, ccp.source_account_id,
		       ccp.created_at, ccp.updated_at, ccp.created_by,
		       pm.name as credit_card_name, a.name as source_account_name
		FROM credit_card_payments ccp
		JOIN payment_methods pm ON ccp.credit_card_id = pm.id
		JOIN accounts a ON ccp.source_account_id = a.id
		WHERE ccp.id = $1
	`, id).Scan(
		&payment.ID,
		&payment.HouseholdID,
		&payment.CreditCardID,
		&payment.Amount,
		&payment.PaymentDate,
		&payment.Notes,
		&payment.SourceAccountID,
		&payment.CreatedAt,
		&payment.UpdatedAt,
		&payment.CreatedBy,
		&payment.CreditCardName,
		&payment.SourceAccountName,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrPaymentNotFound
		}
		return nil, err
	}

	return &payment, nil
}

// Delete deletes a credit card payment
func (r *repository) Delete(ctx context.Context, id string) error {
	result, err := r.pool.Exec(ctx, `
		DELETE FROM credit_card_payments WHERE id = $1
	`, id)

	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return ErrPaymentNotFound
	}

	return nil
}

// ListByHousehold retrieves credit card payments for a household with optional filters
func (r *repository) ListByHousehold(ctx context.Context, householdID string, filter *ListFilter) (*ListResponse, error) {
	query := `
		SELECT ccp.id, ccp.household_id, ccp.credit_card_id, ccp.amount,
		       ccp.payment_date, ccp.notes, ccp.source_account_id,
		       ccp.created_at, ccp.updated_at, ccp.created_by,
		       pm.name as credit_card_name, a.name as source_account_name
		FROM credit_card_payments ccp
		JOIN payment_methods pm ON ccp.credit_card_id = pm.id
		JOIN accounts a ON ccp.source_account_id = a.id
		WHERE ccp.household_id = $1
	`
	args := []any{householdID}
	argNum := 2

	if filter != nil {
		if filter.CreditCardID != nil {
			query += fmt.Sprintf(" AND ccp.credit_card_id = $%d", argNum)
			args = append(args, *filter.CreditCardID)
			argNum++
		}
		if filter.StartDate != nil {
			query += fmt.Sprintf(" AND ccp.payment_date >= $%d", argNum)
			args = append(args, *filter.StartDate)
			argNum++
		}
		if filter.EndDate != nil {
			query += fmt.Sprintf(" AND ccp.payment_date <= $%d", argNum)
			args = append(args, *filter.EndDate)
			argNum++
		}
	}

	query += ` ORDER BY ccp.payment_date DESC`

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var payments []*CreditCardPayment
	var total float64

	for rows.Next() {
		var payment CreditCardPayment
		err := rows.Scan(
			&payment.ID,
			&payment.HouseholdID,
			&payment.CreditCardID,
			&payment.Amount,
			&payment.PaymentDate,
			&payment.Notes,
			&payment.SourceAccountID,
			&payment.CreatedAt,
			&payment.UpdatedAt,
			&payment.CreatedBy,
			&payment.CreditCardName,
			&payment.SourceAccountName,
		)
		if err != nil {
			return nil, err
		}
		payments = append(payments, &payment)
		total += payment.Amount
	}

	if err = rows.Err(); err != nil {
		return nil, err
	}

	return &ListResponse{
		Payments: payments,
		Total:    total,
	}, nil
}
