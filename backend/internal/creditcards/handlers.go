package creditcards

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/blanquicet/gastos/backend/internal/auth"
)

// Handler handles HTTP requests for credit cards summary
type Handler struct {
	service    Service
	authSvc    *auth.Service
	cookieName string
}

// NewHandler creates a new credit cards handler
func NewHandler(service Service, authSvc *auth.Service, cookieName string) *Handler {
	return &Handler{
		service:    service,
		authSvc:    authSvc,
		cookieName: cookieName,
	}
}

// HandleGetSummary handles GET /credit-cards/summary
// Query params:
//   - cycle_date: optional, date within the billing cycle (default: today), format: YYYY-MM-DD
//   - card_ids: optional, comma-separated list of card IDs to filter
//   - owner_ids: optional, comma-separated list of owner user IDs to filter
func (h *Handler) HandleGetSummary(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Get user from session cookie
	cookie, err := r.Cookie(h.cookieName)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	user, err := h.authSvc.GetUserBySession(ctx, cookie.Value)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	// Parse cycle date (default to today)
	cycleDate := time.Now()
	if dateStr := r.URL.Query().Get("cycle_date"); dateStr != "" {
		parsed, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			http.Error(w, "invalid cycle_date format, expected YYYY-MM-DD", http.StatusBadRequest)
			return
		}
		cycleDate = parsed
	}

	// Parse filters
	var filter *SummaryFilter
	cardIDsStr := r.URL.Query().Get("card_ids")
	ownerIDsStr := r.URL.Query().Get("owner_ids")
	
	if cardIDsStr != "" || ownerIDsStr != "" {
		filter = &SummaryFilter{}
		if cardIDsStr != "" {
			filter.CardIDs = strings.Split(cardIDsStr, ",")
		}
		if ownerIDsStr != "" {
			filter.OwnerIDs = strings.Split(ownerIDsStr, ",")
		}
	}

	summary, err := h.service.GetSummary(ctx, user.ID, cycleDate, filter)
	if err != nil {
		if errors.Is(err, ErrNotAuthorized) {
			http.Error(w, "not authorized", http.StatusForbidden)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(summary)
}

// HandleGetCardMovements handles GET /credit-cards/{id}/movements
// Query params:
//   - cycle_date: optional, date within the billing cycle (default: today), format: YYYY-MM-DD
func (h *Handler) HandleGetCardMovements(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Get user from session cookie
	cookie, err := r.Cookie(h.cookieName)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	user, err := h.authSvc.GetUserBySession(ctx, cookie.Value)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	cardID := r.PathValue("id")
	if cardID == "" {
		http.Error(w, "card ID required", http.StatusBadRequest)
		return
	}

	// Parse cycle date (default to today)
	cycleDate := time.Now()
	if dateStr := r.URL.Query().Get("cycle_date"); dateStr != "" {
		parsed, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			http.Error(w, "invalid cycle_date format, expected YYYY-MM-DD", http.StatusBadRequest)
			return
		}
		cycleDate = parsed
	}

	movements, err := h.service.GetCardMovements(ctx, user.ID, cardID, cycleDate)
	if err != nil {
		if errors.Is(err, ErrNotAuthorized) {
			http.Error(w, "not authorized", http.StatusForbidden)
			return
		}
		if errors.Is(err, ErrCardNotFound) {
			http.Error(w, "credit card not found", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(movements)
}
