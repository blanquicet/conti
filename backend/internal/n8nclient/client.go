package n8nclient

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client is an HTTP client for communicating with n8n webhooks.
type Client struct {
	httpClient *http.Client
	webhookURL string
	apiKey     string
}

// Movement represents an expense movement to be recorded.
type Movement struct {
	ID                     string         `json:"id,omitempty"`
	Fecha                  string         `json:"fecha"`
	Tipo                   string         `json:"tipo"`
	Valor                  float64        `json:"valor"`
	Pagador                string         `json:"pagador,omitempty"`
	Contraparte            string         `json:"contraparte,omitempty"`
	MetodoPago             string         `json:"metodo_pago,omitempty"`
	Categoria              string         `json:"categoria,omitempty"`
	Descripcion            string         `json:"descripcion,omitempty"`
	Participantes          []Participante `json:"participantes,omitempty"`
	DividirEquitativamente bool           `json:"dividir_equitativamente,omitempty"`
}

// Participante represents a participant in a shared expense.
type Participante struct {
	Nombre     string  `json:"nombre"`
	Porcentaje float64 `json:"porcentaje"`
}

// Response represents the response from n8n webhook.
type Response struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
	Error   string `json:"error,omitempty"`
}

// New creates a new n8n client.
func New(webhookURL, apiKey string) *Client {
	return &Client{
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		webhookURL: webhookURL,
		apiKey:     apiKey,
	}
}

// RecordMovement sends a movement to n8n for recording.
func (c *Client) RecordMovement(ctx context.Context, movement *Movement) (*Response, error) {
	body, err := json.Marshal(movement)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal movement: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.webhookURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse response body for both success and error cases
	var response Response
	if err := json.Unmarshal(respBody, &response); err != nil {
		// If JSON parsing fails, return raw body in error
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("n8n error (status %d): %s", resp.StatusCode, string(respBody))
		}
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Check HTTP status code
	if resp.StatusCode != http.StatusOK {
		errorMsg := response.Error
		if errorMsg == "" {
			errorMsg = string(respBody)
		}
		return nil, fmt.Errorf("n8n error (status %d): %s", resp.StatusCode, errorMsg)
	}

	return &response, nil
}
