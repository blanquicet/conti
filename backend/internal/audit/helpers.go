package audit

import (
	"context"
	"encoding/json"
	"net/http"
)

// Context keys for request metadata
type contextKey string

const (
	contextKeyIPAddress contextKey = "audit_ip_address"
	contextKeyUserAgent contextKey = "audit_user_agent"
)

// WithRequestMetadata adds IP and User Agent to context from HTTP request
func WithRequestMetadata(ctx context.Context, r *http.Request) context.Context {
	ip := getIPAddress(r)
	ua := getUserAgent(r)
	
	if ip != nil {
		ctx = context.WithValue(ctx, contextKeyIPAddress, *ip)
	}
	if ua != nil {
		ctx = context.WithValue(ctx, contextKeyUserAgent, *ua)
	}
	
	return ctx
}

// getIPAddressFromContext extracts IP from context
func getIPAddressFromContext(ctx context.Context) *string {
	if ip, ok := ctx.Value(contextKeyIPAddress).(string); ok {
		return &ip
	}
	return nil
}

// getUserAgentFromContext extracts User Agent from context
func getUserAgentFromContext(ctx context.Context) *string {
	if ua, ok := ctx.Value(contextKeyUserAgent).(string); ok {
		return &ua
	}
	return nil
}

// StructToMap converts any struct to map[string]interface{} for audit logging
// This uses JSON marshaling/unmarshaling for simplicity and consistency
func StructToMap(v interface{}) map[string]interface{} {
if v == nil {
return nil
}

// Marshal to JSON
data, err := json.Marshal(v)
if err != nil {
return map[string]interface{}{
"error": "failed to convert struct to map",
}
}

// Unmarshal to map
var result map[string]interface{}
if err := json.Unmarshal(data, &result); err != nil {
return map[string]interface{}{
"error": "failed to unmarshal to map",
}
}

return result
}

// StringPtr is a helper to create string pointers
func StringPtr(s string) *string {
return &s
}
