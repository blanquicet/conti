package categories

import (
	"context"

	"github.com/blanquicet/gastos/backend/internal/audit"
	"github.com/blanquicet/gastos/backend/internal/households"
)

// CategoryService implements Service
type CategoryService struct {
	repo          Repository
	householdRepo households.HouseholdRepository
	auditService  audit.Service
}

// NewService creates a new category service
func NewService(repo Repository, householdRepo households.HouseholdRepository, auditService audit.Service) *CategoryService {
	return &CategoryService{
		repo:          repo,
		householdRepo: householdRepo,
		auditService:  auditService,
	}
}

// Create creates a new category
func (s *CategoryService) Create(ctx context.Context, userID string, input *CreateCategoryInput) (*Category, error) {
	// Validate input
	if err := input.Validate(); err != nil {
		return nil, err
	}

	// Get user's household
	householdID, err := s.getUserHouseholdID(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Create category
	category, err := s.repo.Create(ctx, householdID, input)
	if err != nil {
		s.auditService.LogAsync(ctx, &audit.LogInput{
			Action:       audit.ActionCategoryCreated,
			ResourceType: "category",
			UserID:       audit.StringPtr(userID),
			HouseholdID:  audit.StringPtr(householdID),
			Success:      false,
			ErrorMessage: audit.StringPtr(err.Error()),
		})
		return nil, err
	}

	s.auditService.LogAsync(ctx, &audit.LogInput{
		Action:       audit.ActionCategoryCreated,
		ResourceType: "category",
		ResourceID:   audit.StringPtr(category.ID),
		UserID:       audit.StringPtr(userID),
		HouseholdID:  audit.StringPtr(householdID),
		Success:      true,
		NewValues:    audit.StructToMap(category),
	})

	return category, nil
}

// GetByID retrieves a category if user has access to it
func (s *CategoryService) GetByID(ctx context.Context, userID, id string) (*Category, error) {
	// Get category
	category, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Verify user is member of category's household
	_, err = s.householdRepo.GetMemberByUserID(ctx, category.HouseholdID, userID)
	if err != nil {
		if err == households.ErrMemberNotFound {
			return nil, ErrNotAuthorized
		}
		return nil, err
	}

	return category, nil
}

// ListByHousehold lists all categories for user's household
func (s *CategoryService) ListByHousehold(ctx context.Context, userID string, includeInactive bool) (*ListCategoriesResponse, error) {
	// Get user's household
	householdID, err := s.getUserHouseholdID(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Get categories
	categories, err := s.repo.ListByHousehold(ctx, householdID, includeInactive)
	if err != nil {
		return nil, err
	}

	// Note: Grouping is now done via category_groups table in the database
	// The "grouped" field is deprecated and left empty for backwards compatibility
	return &ListCategoriesResponse{
		Categories: categories,
		Grouped:    make(map[string][]*Category),
	}, nil
}

// Update updates a category
func (s *CategoryService) Update(ctx context.Context, userID, id string, input *UpdateCategoryInput) (*Category, error) {
	// Validate input
	if err := input.Validate(); err != nil {
		return nil, err
	}

	// Get category to verify access
	category, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Verify user is member of category's household
	_, err = s.householdRepo.GetMemberByUserID(ctx, category.HouseholdID, userID)
	if err != nil {
		if err == households.ErrMemberNotFound {
			return nil, ErrNotAuthorized
		}
		return nil, err
	}

	// Store old values for audit
	oldValues := audit.StructToMap(category)

	// Update category
	updated, err := s.repo.Update(ctx, id, input)
	if err != nil {
		s.auditService.LogAsync(ctx, &audit.LogInput{
			Action:       audit.ActionCategoryUpdated,
			ResourceType: "category",
			ResourceID:   audit.StringPtr(id),
			UserID:       audit.StringPtr(userID),
			HouseholdID:  audit.StringPtr(category.HouseholdID),
			Success:      false,
			ErrorMessage: audit.StringPtr(err.Error()),
		})
		return nil, err
	}

	s.auditService.LogAsync(ctx, &audit.LogInput{
		Action:       audit.ActionCategoryUpdated,
		ResourceType: "category",
		ResourceID:   audit.StringPtr(id),
		UserID:       audit.StringPtr(userID),
		HouseholdID:  audit.StringPtr(category.HouseholdID),
		Success:      true,
		OldValues:    oldValues,
		NewValues:    audit.StructToMap(updated),
	})

	return updated, nil
}

// Delete deletes a category
func (s *CategoryService) Delete(ctx context.Context, userID, id string) error {
	// Get category to verify access
	category, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return err
	}

	// Verify user is member of category's household
	_, err = s.householdRepo.GetMemberByUserID(ctx, category.HouseholdID, userID)
	if err != nil {
		if err == households.ErrMemberNotFound {
			return ErrNotAuthorized
		}
		return err
	}

	// Store old values for audit
	oldValues := audit.StructToMap(category)

	// Delete category (repository checks if it's used in movements)
	err = s.repo.Delete(ctx, id)
	if err != nil {
		s.auditService.LogAsync(ctx, &audit.LogInput{
			Action:       audit.ActionCategoryDeleted,
			ResourceType: "category",
			ResourceID:   audit.StringPtr(id),
			UserID:       audit.StringPtr(userID),
			HouseholdID:  audit.StringPtr(category.HouseholdID),
			Success:      false,
			ErrorMessage: audit.StringPtr(err.Error()),
		})
		return err
	}

	s.auditService.LogAsync(ctx, &audit.LogInput{
		Action:       audit.ActionCategoryDeleted,
		ResourceType: "category",
		ResourceID:   audit.StringPtr(id),
		UserID:       audit.StringPtr(userID),
		HouseholdID:  audit.StringPtr(category.HouseholdID),
		Success:      true,
		OldValues:    oldValues,
	})

	return nil
}

// Reorder reorders categories
func (s *CategoryService) Reorder(ctx context.Context, userID string, input *ReorderCategoriesInput) error {
	// Validate input
	if err := input.Validate(); err != nil {
		return err
	}

	// Get user's household
	householdID, err := s.getUserHouseholdID(ctx, userID)
	if err != nil {
		return err
	}

	// Verify all categories belong to user's household
	for _, categoryID := range input.CategoryIDs {
		category, err := s.repo.GetByID(ctx, categoryID)
		if err != nil {
			return err
		}
		if category.HouseholdID != householdID {
			return ErrNotAuthorized
		}
	}

	// Reorder
	return s.repo.Reorder(ctx, householdID, input.CategoryIDs)
}

// getUserHouseholdID gets the household ID for a user
func (s *CategoryService) getUserHouseholdID(ctx context.Context, userID string) (string, error) {
	households, err := s.householdRepo.ListByUser(ctx, userID)
	if err != nil {
		return "", err
	}
	if len(households) == 0 {
		return "", ErrNoHousehold
	}
	// User should only have one household (for now)
	return households[0].ID, nil
}
