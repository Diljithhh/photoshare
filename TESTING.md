# Development Testing Guide

## Setup

1. Make sure you have all dependencies installed:
```bash
# Backend dependencies
cd backend
pip install -r requirements.txt

# Frontend dependencies
cd ..
flutter pub get
```

2. Set up environment variables:
```bash
# Copy example env files
cp .env.example .env
cp backend/.env.example backend/.env
```

3. Start the development servers:
```bash
# Make the development script executable
chmod +x dev.sh

# Run both frontend and backend
./dev.sh
```

## Testing Flow

### 1. Photo Upload Testing
- Open http://localhost:3000 in your browser
- Enter an event ID (e.g., "test-event-1")
- Select multiple photos
- Check the console logs for upload progress
- Verify the session link and password are generated

### 2. Photo Selection Testing
- Copy the generated session link
- Open the link in a new browser tab
- Enter the provided password
- Verify you can see all uploaded photos
- Test selecting and deselecting photos
- Click "Save Selections" and verify the success message

### 3. Error Handling Testing
- Try accessing an invalid session ID
- Enter an incorrect password
- Test with expired sessions
- Try selecting non-existent photos
- Test network error scenarios

### 4. API Testing
Use curl or Postman to test the API endpoints:

1. Create Upload Session:
```bash
curl -X POST http://localhost:8000/api/v1/upload \
  -H "Content-Type: application/json" \
  -d '{"event_id": "test-event"}'
```

2. Authenticate Session:
```bash
curl -X POST http://localhost:8000/api/v1/session/{session_id}/auth \
  -H "Content-Type: application/json" \
  -d '{"password": "your-password"}'
```

3. Get Photos:
```bash
curl -X GET http://localhost:8000/api/v1/session/{session_id}/photos \
  -H "Authorization: Bearer your-jwt-token"
```

4. Select Photos:
```bash
curl -X POST http://localhost:8000/api/v1/session/{session_id}/select \
  -H "Authorization: Bearer your-jwt-token" \
  -H "Content-Type: application/json" \
  -d '{"selected_urls": ["url1", "url2"]}'
```

## Common Issues and Solutions

1. CORS Issues
- Check that the backend CORS settings are correct
- Verify the frontend is using the correct API URL
- Check browser console for CORS errors

2. Upload Issues
- Verify S3 bucket permissions
- Check AWS credentials
- Monitor network tab for request/response details

3. Authentication Issues
- Verify JWT token expiration
- Check password hashing
- Monitor token in local storage

## Monitoring and Debugging

1. Backend Logs
- Check the FastAPI server logs for detailed information
- Monitor DynamoDB operations
- Track S3 upload status

2. Frontend Logs
- Use browser developer tools
- Check network requests
- Monitor state changes

3. Database Monitoring
- Use AWS DynamoDB console to view sessions
- Monitor session expiration
- Check data consistency

## Performance Testing

1. Large File Uploads
- Test with multiple large images
- Monitor memory usage
- Check upload timeouts

2. Concurrent Users
- Test multiple sessions simultaneously
- Monitor API response times
- Check resource usage

## Security Testing

1. Authentication
- Test password strength requirements
- Verify JWT token security
- Check session expiration

2. Access Control
- Verify session isolation
- Test authorization headers
- Check URL access restrictions

## Deployment Testing

Before deploying to production:
1. Build the frontend:
```bash
flutter build web --release
```

2. Test the production build:
```bash
python -m http.server 3000 --directory build/web
```

3. Verify all features work in the production build