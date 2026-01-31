package creditcards

import (
	"time"
)

// BillingCycle represents a billing cycle period
type BillingCycle struct {
	StartDate time.Time `json:"start_date"`
	EndDate   time.Time `json:"end_date"`
	Label     string    `json:"label"` // e.g., "Dic 16 - Ene 15"
}

// CardSummary represents a single credit card's summary for a billing cycle
type CardSummary struct {
	ID            string       `json:"id"`
	Name          string       `json:"name"`
	OwnerID       string       `json:"owner_id"`
	OwnerName     string       `json:"owner_name"`
	CutoffDay     *int         `json:"cutoff_day"` // nil means last day of month
	Institution   *string      `json:"institution,omitempty"`
	Last4         *string      `json:"last4,omitempty"`
	BillingCycle  BillingCycle `json:"billing_cycle"` // This card's billing cycle
	TotalCharges  float64      `json:"total_charges"` // Sum of movements paid with this card
	TotalPayments float64      `json:"total_payments"` // Sum of credit_card_payments
	NetDebt       float64      `json:"net_debt"`       // charges - payments
	MovementCount int          `json:"movement_count"`
	PaymentCount  int          `json:"payment_count"`
}

// AccountBalance represents a savings account with its calculated balance
type AccountBalance struct {
	ID      string  `json:"id"`
	Name    string  `json:"name"`
	Type    string  `json:"type"`
	Balance float64 `json:"balance"`
}

// AvailableCash represents the total available cash across savings accounts
type AvailableCash struct {
	Total    float64           `json:"total"`
	Accounts []*AccountBalance `json:"accounts"`
}

// Totals represents aggregate totals across all cards
type Totals struct {
	TotalCharges  float64 `json:"total_charges"`
	TotalPayments float64 `json:"total_payments"`
	TotalDebt     float64 `json:"total_debt"`
}

// SummaryResponse represents the full response for the credit cards summary endpoint
type SummaryResponse struct {
	BillingCycle  BillingCycle   `json:"billing_cycle"`
	Cards         []*CardSummary `json:"cards"`
	Totals        Totals         `json:"totals"`
	AvailableCash AvailableCash  `json:"available_cash"`
	CanPayAll     bool           `json:"can_pay_all"` // available_cash.total >= totals.total_debt
}

// CardMovement represents a movement (charge) on a credit card
type CardMovement struct {
	ID           string    `json:"id"`
	Type         string    `json:"type"` // HOUSEHOLD, SPLIT, DEBT_PAYMENT
	Description  string    `json:"description"`
	Amount       float64   `json:"amount"` // Full amount, not split portion
	MovementDate time.Time `json:"movement_date"`
	CategoryName *string   `json:"category_name,omitempty"`
	PayerName    string    `json:"payer_name"`
}

// CardPayment represents a payment made to a credit card
type CardPayment struct {
	ID                string    `json:"id"`
	Amount            float64   `json:"amount"`
	PaymentDate       time.Time `json:"payment_date"`
	SourceAccountName string    `json:"source_account_name"`
	Notes             *string   `json:"notes,omitempty"`
}

// CardMovementsResponse represents the response for a card's movements endpoint
type CardMovementsResponse struct {
	CreditCard   CardInfo     `json:"credit_card"`
	BillingCycle BillingCycle `json:"billing_cycle"`
	Charges      struct {
		Movements []*CardMovement `json:"movements"`
		Total     float64         `json:"total"`
	} `json:"charges"`
	Payments struct {
		Items []*CardPayment `json:"items"`
		Total float64        `json:"total"`
	} `json:"payments"`
	NetDebt float64 `json:"net_debt"`
}

// CardInfo represents basic credit card info
type CardInfo struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	OwnerName string  `json:"owner_name"`
	CutoffDay *int    `json:"cutoff_day"`
}

// SummaryFilter contains filters for the summary endpoint
type SummaryFilter struct {
	CardIDs  []string // Filter by specific cards
	OwnerIDs []string // Filter by card owners
}
