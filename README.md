# 📸 PhotoShare

A modern, cross-platform photo sharing application built with Flutter and FastAPI. Share photos securely with password-protected sessions and real-time collaboration features.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)
![AWS](https://img.shields.io/badge/Amazon_AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)

## ✨ Features

### 🎯 Core Features
- **Cross-Platform**: Works on iOS, Android, Web, macOS, Windows, and Linux
- **Secure Photo Sharing**: Password-protected photo viewing sessions
- **Real-time Collaboration**: Multiple users can view and select photos simultaneously
- **Cloud Storage**: AWS S3 integration for reliable photo storage
- **Responsive Design**: Beautiful UI that adapts to different screen sizes

### 🔐 Security Features
- **JWT Authentication**: Secure session management
- **Password Protection**: Optional password protection for photo sessions
- **CORS Configuration**: Proper cross-origin resource sharing setup
- **Environment-based Configuration**: Separate configs for development and production

### 🚀 Technical Features
- **FastAPI Backend**: High-performance async API with automatic documentation
- **Flutter Frontend**: Modern, reactive UI with state management
- **AWS S3 Integration**: Scalable cloud storage for photos
- **DynamoDB**: NoSQL database for session management
- **Auto-reload Development**: Hot reload for both frontend and backend

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flutter App   │    │   FastAPI       │    │   AWS Services  │
│   (Frontend)    │◄──►│   (Backend)     │◄──►│   (Cloud)       │
│                 │    │                 │    │                 │
│ • Cross-platform│    │ • REST API      │    │ • S3 Storage    │
│ • State Mgmt    │    │ • JWT Auth      │    │ • DynamoDB      │
│ • Photo Picker  │    │ • File Upload   │    │ • CloudFront    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- **Flutter SDK** (>=3.2.3)
- **Python** (>=3.11)
- **AWS Account** (for S3 and DynamoDB)
- **Git**

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/photoshare.git
cd photoshare
```

### 2. Backend Setup

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Copy environment template
cp .env.example .env

# Edit .env with your AWS credentials
nano .env
```

**Required Environment Variables:**
```env
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_DEFAULT_REGION=ap-south-1
JWT_SECRET_KEY=your_jwt_secret
ENVIRONMENT=development
ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com
```

### 3. Frontend Setup

```bash
# Install Flutter dependencies
flutter pub get

# Copy environment template
cp .env.example .env

# Edit .env with your API configuration
nano .env
```

**Required Environment Variables:**
```env
API_BASE_URL=http://localhost:8000
ENVIRONMENT=development
```

### 4. Run the Application

**Start the Backend:**
```bash
cd backend
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Start the Frontend:**
```bash
# For web
flutter run -d chrome

# For mobile (iOS/Android)
flutter run

# For desktop
flutter run -d macos  # or windows/linux
```

## 📱 Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| **Web** | ✅ Supported | Full feature support |
| **Android** | ✅ Supported | Native performance |
| **iOS** | ✅ Supported | Native performance |
| **macOS** | ✅ Supported | Desktop experience |
| **Windows** | ✅ Supported | Desktop experience |
| **Linux** | ✅ Supported | Desktop experience |

## 🛠️ Development

### Backend Development

```bash
cd backend

# Install development dependencies
pip install -r requirements.txt

# Run with auto-reload
uvicorn app.main:app --reload

# Run tests
pytest

# Format code
black .

# Lint code
flake8
```

### Frontend Development

```bash
# Install dependencies
flutter pub get

# Run in debug mode
flutter run --debug

# Run tests
flutter test

# Analyze code
flutter analyze

# Format code
dart format .
```

### API Documentation

Once the backend is running, visit:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **OpenAPI JSON**: http://localhost:8000/openapi.json

## 📁 Project Structure

```
photoshare/
├── 📱 lib/                    # Flutter frontend
│   ├── screens/              # UI screens
│   ├── services/             # API services
│   ├── models/               # Data models
│   ├── widgets/              # Reusable widgets
│   └── utils/                # Utilities
├── 🚀 backend/               # FastAPI backend
│   ├── app/
│   │   ├── api/              # API endpoints
│   │   ├── core/             # Core functionality
│   │   ├── models/           # Database models
│   │   ├── services/         # Business logic
│   │   └── utils/            # Utilities
│   ├── requirements.txt      # Python dependencies
│   └── .env.example         # Environment template
├── 📄 docs/                  # Documentation
├── 🧪 test/                  # Test files
└── 📋 README.md             # This file
```

## 🔧 Configuration

### AWS Setup

1. **Create S3 Bucket:**
   ```bash
   aws s3 mb s3://your-photoshare-bucket
   ```

2. **Create DynamoDB Table:**
   ```bash
   aws dynamodb create-table \
     --table-name photo_sessions_share \
     --attribute-definitions \
       AttributeName=session_id,AttributeType=S \
     --key-schema \
       AttributeName=session_id,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST
   ```

3. **Configure IAM Permissions:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject"
         ],
         "Resource": "arn:aws:s3:::your-bucket/*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "dynamodb:GetItem",
           "dynamodb:PutItem",
           "dynamodb:UpdateItem",
           "dynamodb:DeleteItem"
         ],
         "Resource": "arn:aws:dynamodb:*:*:table/photo_sessions_share"
       }
     ]
   }
   ```

## 🚀 Deployment

### Backend Deployment (Render)

1. Connect your GitHub repository to Render
2. Set environment variables in Render dashboard
3. Deploy automatically on push to main branch

### Frontend Deployment (Firebase Hosting)

```bash
# Build for web
flutter build web

# Deploy to Firebase
firebase deploy
```

### Docker Deployment

```bash
# Build and run with Docker Compose
docker-compose up --build
```

## 🧪 Testing

### Backend Tests

```bash
cd backend
pytest tests/ -v
```

### Frontend Tests

```bash
flutter test
```

### Integration Tests

```bash
flutter drive --target=test_driver/app.dart
```

## 📊 API Endpoints

### Authentication
- `POST /api/v1/session/{session_id}/auth` - Authenticate session
- `GET /api/v1/session/{session_id}/photos` - Get session photos (protected)

### Photo Management
- `POST /api/v1/upload-photo` - Upload single photo
- `POST /api/v1/upload-multiple-photos` - Upload multiple photos
- `POST /api/v1/generate-upload-urls` - Generate presigned URLs

### Session Management
- `POST /api/v1/session/create` - Create new photo session
- `POST /api/v1/session/{session_id}/select` - Select photos (protected)

### Utilities
- `GET /api/v1/test-s3-connection` - Test S3 connectivity
- `GET /api/v1/direct-access` - Proxy S3 images

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Code Style

- **Backend**: Follow PEP 8, use Black for formatting
- **Frontend**: Follow Dart style guide, use `dart format`
- **Commits**: Use conventional commit messages

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Flutter](https://flutter.dev/) - Cross-platform UI framework
- [FastAPI](https://fastapi.tiangolo.com/) - Modern Python web framework
- [AWS](https://aws.amazon.com/) - Cloud services
- [Material Design](https://material.io/) - Design system

## 📞 Support

- 📧 Email: support@photoshare.app
- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/photoshare/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/yourusername/photoshare/discussions)

## 🗺️ Roadmap

- [ ] **v1.1**: Real-time photo selection updates
- [ ] **v1.2**: Photo editing capabilities
- [ ] **v1.3**: Advanced sharing options
- [ ] **v1.4**: Mobile app store releases
- [ ] **v2.0**: AI-powered photo organization

---

<div align="center">
  <p>Made with ❤️ by the PhotoShare Team</p>
  <p>
    <a href="https://github.com/yourusername/photoshare">⭐ Star us on GitHub</a> •
    <a href="https://twitter.com/photoshare">🐦 Follow us on Twitter</a> •
    <a href="https://photoshare.app">🌐 Visit our website</a>
  </p>
</div>
