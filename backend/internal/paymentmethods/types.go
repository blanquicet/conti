package paymentmethods

import (
"context"
"errors"
"time"
)

// Errors for payment method operations
var (
ErrPaymentMethodNotFound     = errors.New("payment method not found")
ErrPaymentMethodNameExists   = errors.New("payment method name already exists in household")
ErrNotAuthorized             = errors.New("not authorized")
ErrInvalidPaymentMethodType  = errors.New("invalid payment method type")
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

// Populated from joins - not in DB table
OwnerName              string            `json:"owner_name,omitempty"`
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
