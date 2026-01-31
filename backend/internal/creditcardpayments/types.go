package creditcardpayments

import (
	"context"
	"errors"
	"time"
)

// Errors for credit card payment operations
var (
	ErrPaymentNotFound          = errors.New("credit card payment not found")
	ErrNotAuthorized            = errors.New("not authorized")
	ErrInvalidAmount            = errors.New("amount must be greater than 0")
	ErrCreditCardNotFound       = errors.New("credit card not found")
	ErrSourceAccountNotFound    = errors.New("source account not found")
	ErrNotACreditCard           = errors.New("payment method is not a credit card")
	ErrSourceMustBeSavings      = errors.New("source account must be a savings account")
)

// CreditCardPayment represents a payment made to a credit card
type CreditCardPayment struct {
	ID                string    `json:"id"`
	HouseholdID       string    `json:"household_id"`
	CreditCardID      string    `json:"credit_card_id"`
	Amount            float64   `json:"amount"`
	PaymentDate       time.Time `json:"payment_date"`
	Notes             *string   `json:"notes,omitempty"`
	SourceAccountID   string    `json:"source_account_id"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
	CreatedBy         string    `json:"created_by"`

	// Populated from joins - not in DB table
	CreditCardName    string    `json:"credit_card_name,omitempty"`
	SourceAccountName string    `json:"source_account_name,omitempty"`
}

// CreateInput contains the fields needed to create a credit card payment
type CreateInput struct {
	CreditCardID    string    `json:"credit_card_id"`
	Amount          float64   `json:"amount"`
	PaymentDate     time.Time `json:"payment_date"`
	Notes           *string   `json:"notes,omitempty"`
	SourceAccountID string    `json:"source_account_id"`
}

// Validate validates the create input
func (i *CreateInput) Validate() error {
	if i.CreditCardID == "" {
		return errors.New("credit_card_id is required")
	}
	if i.Amount <= 0 {
		return ErrInvalidAmount
	}
	if i.SourceAccountID == "" {
		return errors.New("source_account_id is required")
	}
	if i.PaymentDate.IsZero() {
		return errors.New("payment_date is required")
	}
	return nil
}

// ListFilter contains filters for listing credit card payments
type ListFilter struct {
	CreditCardID *string
	StartDate    *time.Time
	EndDate      *time.Time
}

// ListResponse contains the list of payments and totals
type ListResponse struct {
	Payments []*CreditCardPayment `json:"payments"`
	Total    float64              `json:"total"`
}

// Repository defines the interface for credit card payment persistence
type Repository interface {
	Create(ctx context.Context, payment *CreditCardPayment) (*CreditCardPayment, error)
	GetByID(ctx context.Context, id string) (*CreditCardPayment, error)
	Delete(ctx context.Context, id string) error
	ListByHousehold(ctx context.Context, householdID string, filter *ListFilter) (*ListResponse, error)
}

// Service defines the interface for credit card payment business logic
type Service interface {
	Create(ctx context.Context, userID string, input *CreateInput) (*CreditCardPayment, error)
	GetByID(ctx context.Context, userID, id string) (*CreditCardPayment, error)
	Delete(ctx context.Context, userID, id string) error
	List(ctx context.Context, userID string, filter *ListFilter) (*ListResponse, error)
}
