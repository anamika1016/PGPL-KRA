# KRA System

## Department Management - Delete Functionality

### Problem Fixed
Previously, when deleting a department, the system would delete ALL users and activities in that department. This caused issues when you only wanted to remove a specific user from a department.

### New Solution
The system now provides two separate delete options:

1. **Delete User** (Orange button) - Removes only a specific user's activities from a department
   - Only affects the selected employee
   - Other users in the same department remain unaffected
   - If this was the only user in the department, the department is also deleted

2. **Delete Dept** (Red button) - Removes the entire department and all associated data
   - Deletes all users, activities, and achievements in that department
   - Use this only when you want to completely remove a department

### How It Works
- **Delete User**: Uses the `delete_user_activities` route to remove specific user data
- **Delete Dept**: Uses the existing `destroy` method to remove the entire department
- The system automatically handles cascading deletes for related records (achievements, remarks, etc.)

### Technical Details
- New route: `POST /departments/:id/delete_user_activities`
- New method: `delete_user_activities_from_department(user_id)`
- Updated view with separate buttons for each delete action
- Improved user experience with clear visual distinction between actions

### Usage
1. Navigate to the Departments page
2. For each department entry, you'll see two delete buttons:
   - **Delete User** (Orange) - Removes specific user
   - **Delete Dept** (Red) - Removes entire department
3. Click the appropriate button based on your needs
4. Confirm the action when prompted

This ensures that deleting one user doesn't affect other users in the same department.
