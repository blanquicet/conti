package movements

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/blanquicet/gastos/backend/internal/n8nclient"
)

// Handler handles movement-related HTTP requests.
type Handler struct {
	n8nClient *n8nclient.Client
	logger    *slog.Logger
}

// NewHandler creates a new movements handler.
func NewHandler(n8nClient *n8nclient.Client, logger *slog.Logger) *Handler {
	return &Handler{
		n8nClient: n8nClient,
		logger:    logger,
	}
}

// RecordMovement proxies movement registration to n8n.
// POST /movements
func (h *Handler) RecordMovement(w http.ResponseWriter, r *http.Request) {
	var movement n8nclient.Movement

	if err := json.NewDecoder(r.Body).Decode(&movement); err != nil {
		h.logger.Error("failed to decode movement", "error", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Forward to n8n
	resp, err := h.n8nClient.RecordMovement(r.Context(), &movement)
	if err != nil {
		h.logger.Error("failed to record movement in n8n", "error", err)
		http.Error(w, "Failed to record movement", http.StatusInternalServerError)
		return
	}

	// Return n8n's response
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		h.logger.Error("failed to encode response", "error", err)
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}
}
