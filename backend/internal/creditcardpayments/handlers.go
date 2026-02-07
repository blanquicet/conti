package creditcardpayments

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/blanquicet/conti/backend/internal/auth"
)

// Handler handles HTTP requests for credit card payments
type Handler struct {
	service    Service
	authSvc    *auth.Service
	cookieName string
	logger     *slog.Logger
}

// NewHandler creates a new credit card payment handler
func NewHandler(service Service, authService *auth.Service, cookieName string, logger *slog.Logger) *Handler {
	return &Handler{
		service:    service,
		authSvc:    authService,
		cookieName: cookieName,
		logger:     logger,
	}
}

// CreateRequest represents the request body for creating a credit card payment
type CreateRequest struct {
	CreditCardID    string  `json:"credit_card_id"`
	Amount          float64 `json:"amount"`
	PaymentDate     string  `json:"payment_date"` // YYYY-MM-DD format
	Notes           *string `json:"notes,omitempty"`
	SourceAccountID string  `json:"source_account_id"`
}

// getUserFromSession extracts user from session cookie
func (h *Handler) getUserFromSession(r *http.Request) (*auth.User, error) {
	cookie, err := r.Cookie(h.cookieName)
	if err != nil {
		return nil, err
	}
	return h.authSvc.GetUserBySession(r.Context(), cookie.Value)
}

// HandleCreate handles POST /credit-card-payments
func (h *Handler) HandleCreate(w http.ResponseWriter, r *http.Request) {
	user, err := h.getUserFromSession(r)
	if err != nil {
		h.logger.Error("unauthorized", "error", err)
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var req CreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Parse payment date
	paymentDate, err := time.Parse("2006-01-02", req.PaymentDate)
	if err != nil {
		http.Error(w, "Invalid payment_date format, use YYYY-MM-DD", http.StatusBadRequest)
		return
	}

	input := &CreateInput{
		CreditCardID:    req.CreditCardID,
		Amount:          req.Amount,
		PaymentDate:     paymentDate,
		Notes:           req.Notes,
		SourceAccountID: req.SourceAccountID,
	}

	payment, err := h.service.Create(r.Context(), user.ID, input)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidAmount):
			http.Error(w, err.Error(), http.StatusBadRequest)
		case errors.Is(err, ErrCreditCardNotFound):
			http.Error(w, err.Error(), http.StatusNotFound)
		case errors.Is(err, ErrSourceAccountNotFound):
			http.Error(w, err.Error(), http.StatusNotFound)
		case errors.Is(err, ErrNotACreditCard):
			http.Error(w, err.Error(), http.StatusBadRequest)
		case errors.Is(err, ErrSourceMustBeSavings):
			http.Error(w, err.Error(), http.StatusBadRequest)
		case errors.Is(err, ErrNotAuthorized):
			http.Error(w, err.Error(), http.StatusForbidden)
		default:
			h.logger.Error("failed to create payment", "error", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(payment)
}

// HandleGet handles GET /credit-card-payments/:id
func (h *Handler) HandleGet(w http.ResponseWriter, r *http.Request) {
	user, err := h.getUserFromSession(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	paymentID := r.PathValue("id")

	payment, err := h.service.GetByID(r.Context(), user.ID, paymentID)
	if err != nil {
		switch {
		case errors.Is(err, ErrPaymentNotFound):
			http.Error(w, err.Error(), http.StatusNotFound)
		case errors.Is(err, ErrNotAuthorized):
			http.Error(w, err.Error(), http.StatusForbidden)
		default:
			http.Error(w, "Internal server error", http.StatusInternalServerError)
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(payment)
}

// HandleDelete handles DELETE /credit-card-payments/:id
func (h *Handler) HandleDelete(w http.ResponseWriter, r *http.Request) {
	user, err := h.getUserFromSession(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	paymentID := r.PathValue("id")

	err = h.service.Delete(r.Context(), user.ID, paymentID)
	if err != nil {
		switch {
		case errors.Is(err, ErrPaymentNotFound):
			http.Error(w, err.Error(), http.StatusNotFound)
		case errors.Is(err, ErrNotAuthorized):
			http.Error(w, err.Error(), http.StatusForbidden)
		default:
			http.Error(w, "Internal server error", http.StatusInternalServerError)
		}
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleList handles GET /credit-card-payments
func (h *Handler) HandleList(w http.ResponseWriter, r *http.Request) {
	user, err := h.getUserFromSession(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var filter ListFilter

	// Parse query parameters
	if cardID := r.URL.Query().Get("credit_card_id"); cardID != "" {
		filter.CreditCardID = &cardID
	}
	if startDate := r.URL.Query().Get("start_date"); startDate != "" {
		if t, err := time.Parse("2006-01-02", startDate); err == nil {
			filter.StartDate = &t
		}
	}
	if endDate := r.URL.Query().Get("end_date"); endDate != "" {
		if t, err := time.Parse("2006-01-02", endDate); err == nil {
			filter.EndDate = &t
		}
	}

	result, err := h.service.List(r.Context(), user.ID, &filter)
	if err != nil {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
