package paymentmethods

import (
"context"
"errors"
"time"
)

// Errors for payment method operations
var (
ErrPaymentMethodNotFound       = errors.New("payment method not found")
ErrPaymentMethodNameExists     = errors.New("payment method name already exists in household")
ErrNotAuthorized               = errors.New("not authorized")
ErrInvalidPaymentMethodType    = errors.New("invalid payment method type")
ErrCutoffDayOnlyForCreditCards = errors.New("cutoff_day is only applicable for credit cards")
ErrLinkedAccountRequired       = errors.New("linked_account_id is required for debit cards")
ErrLinkedAccountMustBeSavings  = errors.New("linked account must be a savings account")
ErrInvalidCutoffDay            = errors.New("cutoff_day must be between 1 and 31")
)

// PaymentMethodType represents the type of payment method
type PaymentMethodType string

const (
TypeCreditCard PaymentMethodType = "credit_card"
TypeDebitCard  PaymentMethodType = "debit_card"
TypeCash       PaymentMethodType = "cash"
TypeOther      PaymentMethodType = "other"
)

// Validate checks if the payment method type is valid
func (t PaymentMethodType) Validate() error {
switch t {
case TypeCreditCard, TypeDebitCard, TypeCash, TypeOther:
return nil
default:
return ErrInvalidPaymentMethodType
}
}

// PaymentMethod represents a payment method (credit card, bank account, etc.)
type PaymentMethod struct {
ID                     string            `json:"id"`
HouseholdID            string            `json:"household_id"`
OwnerID                string            `json:"owner_id"`
Name                   string            `json:"name"`
Type                   PaymentMethodType `json:"type"`
IsSharedWithHousehold  bool              `json:"is_shared_with_household"`
Last4                  *string           `json:"last4,omitempty"`
Institution            *string           `json:"institution,omitempty"`
Notes                  *string           `json:"notes,omitempty"`
IsActive               bool              `json:"is_active"`
CreatedAt              time.Time         `json:"created_at"`
UpdatedAt              time.Time         `json:"updated_at"`

// Credit card specific: billing cycle cut-off day (1-31, NULL = last day of month)
CutoffDay              *int              `json:"cutoff_day,omitempty"`

// Debit card specific: linked savings account for balance tracking
LinkedAccountID        *string           `json:"linked_account_id,omitempty"`

// Populated from joins - not in DB table
OwnerName              string            `json:"owner_name,omitempty"`
LinkedAccountName      *string           `json:"linked_account_name,omitempty"`
}

// Validate validates payment method fields
func (p *PaymentMethod) Validate() error {
if p.Name == "" {
return errors.New("payment method name is required")
}
if len(p.Name) > 100 {
return errors.New("payment method name must be 100 characters or less")
}
if err := p.Type.Validate(); err != nil {
return err
}
if p.Last4 != nil && len(*p.Last4) != 4 {
return errors.New("last4 must be exactly 4 characters")
}
if p.Institution != nil && len(*p.Institution) > 100 {
return errors.New("institution must be 100 characters or less")
}
// Validate cutoff_day: only for credit cards, must be 1-31
if p.CutoffDay != nil {
if p.Type != TypeCreditCard {
return ErrCutoffDayOnlyForCreditCards
}
if *p.CutoffDay < 1 || *p.CutoffDay > 31 {
return ErrInvalidCutoffDay
}
}
// Note: linked_account_id validation (required for debit cards, must be savings)
// is done in the service layer where we can check the account type
return nil
}

// Repository defines the interface for payment method persistence
type Repository interface {
Create(ctx context.Context, pm *PaymentMethod) (*PaymentMethod, error)
GetByID(ctx context.Context, id string) (*PaymentMethod, error)
Update(ctx context.Context, pm *PaymentMethod) (*PaymentMethod, error)
Delete(ctx context.Context, id string) error
ListByHousehold(ctx context.Context, householdID string) ([]*PaymentMethod, error)
FindByName(ctx context.Context, householdID, name string) (*PaymentMethod, error)
}
