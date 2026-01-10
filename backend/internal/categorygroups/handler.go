package categorygroups

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/blanquicet/gastos/backend/internal/auth"
)

// Handler handles HTTP requests for category groups
type Handler struct {
	service    Service
	authSvc    *auth.Service
	logger     *slog.Logger
	cookieName string
}

// NewHandler creates a new category groups handler
func NewHandler(service Service, authService *auth.Service, cookieName string, logger *slog.Logger) *Handler {
	return &Handler{
		service:    service,
		authSvc:    authService,
		logger:     logger,
		cookieName: cookieName,
	}
}

// ListCategoryGroups returns all category groups with their categories for the current user's household
func (h *Handler) ListCategoryGroups(w http.ResponseWriter, r *http.Request) {
	// Get user from session
	user, err := h.getUserFromSession(r)
	if err != nil {
		h.logger.Error("failed to get user from session", "error", err)
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	groups, err := h.service.ListByHousehold(r.Context(), user.ID)
	if err != nil {
		h.logger.Error("failed to list category groups", "error", err, "user_id", user.ID)
		if err == ErrNoHousehold {
			http.Error(w, "user has no household", http.StatusNotFound)
			return
		}
		http.Error(w, "Failed to fetch category groups", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(groups); err != nil {
		h.logger.Error("failed to encode category groups response", "error", err)
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}
}

// getUserFromSession is a helper to extract user from session cookie
func (h *Handler) getUserFromSession(r *http.Request) (*auth.User, error) {
	cookie, err := r.Cookie(h.cookieName)
	if err != nil {
		return nil, err
	}
	return h.authSvc.GetUserBySession(r.Context(), cookie.Value)
}
