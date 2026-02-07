package creditcardpayments

import (
	"context"
	"log/slog"

	"github.com/blanquicet/conti/backend/internal/accounts"
	"github.com/blanquicet/conti/backend/internal/audit"
	"github.com/blanquicet/conti/backend/internal/households"
	"github.com/blanquicet/conti/backend/internal/paymentmethods"
)

// service implements Service
type service struct {
	repo               Repository
	householdRepo      households.HouseholdRepository
	paymentMethodsRepo paymentmethods.Repository
	accountsRepo       accounts.Repository
	auditService       audit.Service
	logger             *slog.Logger
}

// NewService creates a new credit card payment service
func NewService(
	repo Repository,
	householdRepo households.HouseholdRepository,
	paymentMethodsRepo paymentmethods.Repository,
	accountsRepo accounts.Repository,
	auditService audit.Service,
	logger *slog.Logger,
) Service {
	return &service{
		repo:               repo,
		householdRepo:      householdRepo,
		paymentMethodsRepo: paymentMethodsRepo,
		accountsRepo:       accountsRepo,
		auditService:       auditService,
		logger:             logger,
	}
}

// Create creates a new credit card payment
func (s *service) Create(ctx context.Context, userID string, input *CreateInput) (*CreditCardPayment, error) {
	// Validate input
	if err := input.Validate(); err != nil {
		return nil, err
	}

	// Get user's household
	householdID, err := s.householdRepo.GetUserHouseholdID(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Verify credit card exists and is a credit card
	creditCard, err := s.paymentMethodsRepo.GetByID(ctx, input.CreditCardID)
	if err != nil {
		if err == paymentmethods.ErrPaymentMethodNotFound {
			return nil, ErrCreditCardNotFound
		}
		return nil, err
	}
	if creditCard.HouseholdID != householdID {
		return nil, ErrNotAuthorized
	}
	if creditCard.Type != paymentmethods.TypeCreditCard {
		return nil, ErrNotACreditCard
	}

	// Verify source account exists and is a savings account
	sourceAccount, err := s.accountsRepo.GetByID(ctx, input.SourceAccountID)
	if err != nil {
		if err == accounts.ErrAccountNotFound {
			return nil, ErrSourceAccountNotFound
		}
		return nil, err
	}
	if sourceAccount.HouseholdID != householdID {
		return nil, ErrNotAuthorized
	}
	if sourceAccount.Type != accounts.TypeSavings {
		return nil, ErrSourceMustBeSavings
	}

	// Create the payment
	payment := &CreditCardPayment{
		HouseholdID:     householdID,
		CreditCardID:    input.CreditCardID,
		Amount:          input.Amount,
		PaymentDate:     input.PaymentDate,
		Notes:           input.Notes,
		SourceAccountID: input.SourceAccountID,
		CreatedBy:       userID,
	}

	result, err := s.repo.Create(ctx, payment)
	if err != nil {
		s.auditService.LogAsync(ctx, &audit.LogInput{
			UserID:       audit.StringPtr(userID),
			Action:       audit.ActionCreditCardPaymentCreated,
			ResourceType: "credit_card_payment",
			HouseholdID:  audit.StringPtr(householdID),
			Success:      false,
			ErrorMessage: audit.StringPtr(err.Error()),
		})
		return nil, err
	}

	// Add names from the lookups we already did
	result.CreditCardName = creditCard.Name
	result.SourceAccountName = sourceAccount.Name

	// Log successful creation
	s.auditService.LogAsync(ctx, &audit.LogInput{
		UserID:       audit.StringPtr(userID),
		Action:       audit.ActionCreditCardPaymentCreated,
		ResourceType: "credit_card_payment",
		ResourceID:   audit.StringPtr(result.ID),
		HouseholdID:  audit.StringPtr(householdID),
		NewValues:    audit.StructToMap(result),
		Success:      true,
	})

	return result, nil
}

// GetByID retrieves a credit card payment by ID
func (s *service) GetByID(ctx context.Context, userID, id string) (*CreditCardPayment, error) {
	// Get user's household
	householdID, err := s.householdRepo.GetUserHouseholdID(ctx, userID)
	if err != nil {
		return nil, err
	}

	payment, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Verify authorization
	if payment.HouseholdID != householdID {
		return nil, ErrNotAuthorized
	}

	return payment, nil
}

// Delete deletes a credit card payment
func (s *service) Delete(ctx context.Context, userID, id string) error {
	// Get user's household
	householdID, err := s.householdRepo.GetUserHouseholdID(ctx, userID)
	if err != nil {
		return err
	}

	// Get payment to verify ownership
	payment, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return err
	}

	if payment.HouseholdID != householdID {
		return ErrNotAuthorized
	}

	// Delete the payment
	err = s.repo.Delete(ctx, id)
	if err != nil {
		s.auditService.LogAsync(ctx, &audit.LogInput{
			UserID:       audit.StringPtr(userID),
			Action:       audit.ActionCreditCardPaymentDeleted,
			ResourceType: "credit_card_payment",
			ResourceID:   audit.StringPtr(id),
			HouseholdID:  audit.StringPtr(householdID),
			Success:      false,
			ErrorMessage: audit.StringPtr(err.Error()),
		})
		return err
	}

	// Log successful deletion
	s.auditService.LogAsync(ctx, &audit.LogInput{
		UserID:       audit.StringPtr(userID),
		Action:       audit.ActionCreditCardPaymentDeleted,
		ResourceType: "credit_card_payment",
		ResourceID:   audit.StringPtr(id),
		HouseholdID:  audit.StringPtr(householdID),
		OldValues:    audit.StructToMap(payment),
		Success:      true,
	})

	return nil
}

// List lists credit card payments for the user's household
func (s *service) List(ctx context.Context, userID string, filter *ListFilter) (*ListResponse, error) {
	// Get user's household
	householdID, err := s.householdRepo.GetUserHouseholdID(ctx, userID)
	if err != nil {
		return nil, err
	}

	return s.repo.ListByHousehold(ctx, householdID, filter)
}
