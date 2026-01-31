package creditcards

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/blanquicet/gastos/backend/internal/households"
	"github.com/blanquicet/gastos/backend/internal/paymentmethods"
)

var (
	ErrNotAuthorized = errors.New("not authorized to access this resource")
	ErrCardNotFound  = errors.New("credit card not found")
)

// Service handles business logic for credit card summaries
type Service interface {
	GetSummary(ctx context.Context, userID string, cycleDate time.Time, filter *SummaryFilter) (*SummaryResponse, error)
	GetCardMovements(ctx context.Context, userID string, cardID string, cycleDate time.Time) (*CardMovementsResponse, error)
}

type service struct {
	repo               Repository
	householdsRepo     households.HouseholdRepository
	paymentMethodsRepo paymentmethods.Repository
	logger             *slog.Logger
}

// NewService creates a new credit cards service
func NewService(
	repo Repository,
	householdsRepo households.HouseholdRepository,
	paymentMethodsRepo paymentmethods.Repository,
	logger *slog.Logger,
) Service {
	return &service{
		repo:               repo,
		householdsRepo:     householdsRepo,
		paymentMethodsRepo: paymentMethodsRepo,
		logger:             logger,
	}
}

// GetSummary returns the credit cards summary for a billing cycle
func (s *service) GetSummary(ctx context.Context, userID string, cycleDate time.Time, filter *SummaryFilter) (*SummaryResponse, error) {
	// Get household ID for authorization
	householdID, err := s.householdsRepo.GetUserHouseholdID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("get household: %w", err)
	}

	// Get all credit cards
	cards, err := s.repo.GetCreditCards(ctx, householdID)
	if err != nil {
		return nil, fmt.Errorf("get credit cards: %w", err)
	}

	// Apply filters if provided
	if filter != nil {
		cards = s.applyFilters(cards, filter)
	}

	// Calculate calendar month for payments (1st to last day of the month)
	calendarMonthStart := time.Date(cycleDate.Year(), cycleDate.Month(), 1, 0, 0, 0, 0, cycleDate.Location())
	calendarMonthEnd := calendarMonthStart.AddDate(0, 1, 0) // First day of next month

	var totals Totals

	// Calculate billing cycle and charges/payments for each card
	for _, card := range cards {
		cycle := CalculateBillingCycle(cycleDate, card.CutoffDay)
		card.BillingCycle = cycle

		// Charges use the card's billing cycle
		movements, chargesTotal, err := s.repo.GetCardCharges(ctx, card.ID, cycle.StartDate, cycle.EndDate)
		if err != nil {
			return nil, fmt.Errorf("get card charges for %s: %w", card.ID, err)
		}

		// Payments use calendar month (1st to last day)
		payments, paymentsTotal, err := s.repo.GetCardPayments(ctx, card.ID, calendarMonthStart, calendarMonthEnd)
		if err != nil {
			return nil, fmt.Errorf("get card payments for %s: %w", card.ID, err)
		}

		card.TotalCharges = chargesTotal
		card.TotalPayments = paymentsTotal
		card.NetDebt = chargesTotal - paymentsTotal
		card.MovementCount = len(movements)
		card.PaymentCount = len(payments)

		totals.TotalCharges += chargesTotal
		totals.TotalPayments += paymentsTotal
	}

	totals.TotalDebt = totals.TotalCharges - totals.TotalPayments

	// Get available cash (savings + cash account balances)
	balances, err := s.repo.GetSavingsBalances(ctx, householdID, cycleDate)
	if err != nil {
		return nil, fmt.Errorf("get savings balances: %w", err)
	}

	var availableCash AvailableCash
	availableCash.Accounts = balances
	for _, acc := range balances {
		availableCash.Total += acc.Balance
	}

	// Calculate billing cycle for response (use first card's cutoff or default)
	var defaultCutoff *int
	if len(cards) > 0 {
		defaultCutoff = cards[0].CutoffDay
	}
	cycle := CalculateBillingCycle(cycleDate, defaultCutoff)

	return &SummaryResponse{
		BillingCycle:  cycle,
		Cards:         cards,
		Totals:        totals,
		AvailableCash: availableCash,
		CanPayAll:     availableCash.Total >= totals.TotalDebt,
	}, nil
}

// GetCardMovements returns detailed movements and payments for a single card
func (s *service) GetCardMovements(ctx context.Context, userID string, cardID string, cycleDate time.Time) (*CardMovementsResponse, error) {
	// Get household ID for authorization
	householdID, err := s.householdsRepo.GetUserHouseholdID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("get household: %w", err)
	}

	// Get the credit card and verify ownership
	card, err := s.paymentMethodsRepo.GetByID(ctx, cardID)
	if err != nil {
		if errors.Is(err, paymentmethods.ErrPaymentMethodNotFound) {
			return nil, ErrCardNotFound
		}
		return nil, fmt.Errorf("get credit card: %w", err)
	}

	if card.HouseholdID != householdID {
		return nil, ErrNotAuthorized
	}

	if card.Type != "credit_card" {
		return nil, ErrCardNotFound
	}

	// Calculate billing cycle for this card (used for charges)
	cycle := CalculateBillingCycle(cycleDate, card.CutoffDay)

	// Calculate calendar month for payments (1st to last day of the month)
	calendarMonthStart := time.Date(cycleDate.Year(), cycleDate.Month(), 1, 0, 0, 0, 0, cycleDate.Location())
	calendarMonthEnd := calendarMonthStart.AddDate(0, 1, 0) // First day of next month

	// Get movements (charges) - uses billing cycle
	movements, chargesTotal, err := s.repo.GetCardCharges(ctx, card.ID, cycle.StartDate, cycle.EndDate)
	if err != nil {
		return nil, fmt.Errorf("get card charges: %w", err)
	}

	// Get payments - uses calendar month
	payments, paymentsTotal, err := s.repo.GetCardPayments(ctx, card.ID, calendarMonthStart, calendarMonthEnd)
	if err != nil {
		return nil, fmt.Errorf("get card payments: %w", err)
	}

	response := &CardMovementsResponse{
		CreditCard: CardInfo{
			ID:        card.ID,
			Name:      card.Name,
			OwnerName: card.OwnerName,
			CutoffDay: card.CutoffDay,
		},
		BillingCycle: cycle,
		NetDebt:      chargesTotal - paymentsTotal,
	}

	response.Charges.Movements = movements
	response.Charges.Total = chargesTotal
	response.Payments.Items = payments
	response.Payments.Total = paymentsTotal

	return response, nil
}

// applyFilters filters cards based on the provided filter criteria
func (s *service) applyFilters(cards []*CardSummary, filter *SummaryFilter) []*CardSummary {
	if len(filter.CardIDs) == 0 && len(filter.OwnerIDs) == 0 {
		return cards
	}

	cardIDSet := make(map[string]bool)
	for _, id := range filter.CardIDs {
		cardIDSet[id] = true
	}

	ownerIDSet := make(map[string]bool)
	for _, id := range filter.OwnerIDs {
		ownerIDSet[id] = true
	}

	var filtered []*CardSummary
	for _, card := range cards {
		// If cardIDs filter is set, card must be in the list
		if len(cardIDSet) > 0 && !cardIDSet[card.ID] {
			continue
		}
		// If ownerIDs filter is set, owner must be in the list
		if len(ownerIDSet) > 0 && !ownerIDSet[card.OwnerID] {
			continue
		}
		filtered = append(filtered, card)
	}

	return filtered
}

// CalculateBillingCycle calculates the billing cycle for a given date and cutoff day
// cutoffDay nil means last day of the month
func CalculateBillingCycle(date time.Time, cutoffDay *int) BillingCycle {
	year := date.Year()
	month := date.Month()
	day := date.Day()

	var cutoff int
	if cutoffDay == nil {
		// Use last day of current month
		cutoff = lastDayOfMonth(year, month)
	} else {
		cutoff = *cutoffDay
	}

	var startDate, endDate time.Time

	// If current day is after cutoff, cycle is from this month's cutoff+1 to next month's cutoff
	// If current day is before/equal cutoff, cycle is from last month's cutoff+1 to this month's cutoff
	if day > cutoff {
		// Cycle: this month's (cutoff+1) to next month's cutoff
		startDate = time.Date(year, month, cutoff+1, 0, 0, 0, 0, date.Location())
		
		nextMonth := month + 1
		nextYear := year
		if nextMonth > 12 {
			nextMonth = 1
			nextYear++
		}
		
		// Handle cutoff for next month (might be smaller, e.g., Feb)
		nextCutoff := cutoff
		lastDay := lastDayOfMonth(nextYear, nextMonth)
		if nextCutoff > lastDay {
			nextCutoff = lastDay
		}
		endDate = time.Date(nextYear, nextMonth, nextCutoff, 23, 59, 59, 999999999, date.Location())
	} else {
		// Cycle: last month's (cutoff+1) to this month's cutoff
		prevMonth := month - 1
		prevYear := year
		if prevMonth < 1 {
			prevMonth = 12
			prevYear--
		}
		
		// Handle cutoff for previous month
		prevCutoff := cutoff
		lastDay := lastDayOfMonth(prevYear, prevMonth)
		if prevCutoff > lastDay {
			prevCutoff = lastDay
		}
		startDate = time.Date(prevYear, prevMonth, prevCutoff+1, 0, 0, 0, 0, date.Location())
		
		// This month's cutoff
		thisCutoff := cutoff
		thisLastDay := lastDayOfMonth(year, month)
		if thisCutoff > thisLastDay {
			thisCutoff = thisLastDay
		}
		endDate = time.Date(year, month, thisCutoff, 23, 59, 59, 999999999, date.Location())
	}

	// Format label
	label := formatCycleLabel(startDate, endDate)

	return BillingCycle{
		StartDate: startDate,
		EndDate:   endDate,
		Label:     label,
	}
}

// lastDayOfMonth returns the last day of the given month
func lastDayOfMonth(year int, month time.Month) int {
	// Go to first day of next month, then subtract one day
	firstOfNext := time.Date(year, month+1, 1, 0, 0, 0, 0, time.UTC)
	lastOfMonth := firstOfNext.AddDate(0, 0, -1)
	return lastOfMonth.Day()
}

// formatCycleLabel creates a human-readable label for the billing cycle
func formatCycleLabel(start, end time.Time) string {
	months := map[time.Month]string{
		time.January:   "Ene",
		time.February:  "Feb",
		time.March:     "Mar",
		time.April:     "Abr",
		time.May:       "May",
		time.June:      "Jun",
		time.July:      "Jul",
		time.August:    "Ago",
		time.September: "Sep",
		time.October:   "Oct",
		time.November:  "Nov",
		time.December:  "Dic",
	}

	startMonth := months[start.Month()]
	endMonth := months[end.Month()]

	return fmt.Sprintf("%s %d - %s %d", startMonth, start.Day(), endMonth, end.Day())
}
