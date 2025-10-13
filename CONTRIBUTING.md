# Contributing to PhotoShare

Thank you for your interest in contributing to PhotoShare! We welcome contributions from the community and are grateful for your help in making this project better.

## 🤝 How to Contribute

### Reporting Issues

- **Bug Reports**: Use the GitHub issue tracker to report bugs
- **Feature Requests**: Suggest new features or improvements
- **Documentation**: Help improve our documentation

### Making Changes

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**
4. **Test your changes**
5. **Commit your changes**: `git commit -m 'Add amazing feature'`
6. **Push to the branch**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

## 📋 Development Guidelines

### Code Style

#### Backend (Python/FastAPI)
- Follow [PEP 8](https://pep8.org/) style guide
- Use [Black](https://black.readthedocs.io/) for code formatting
- Use [flake8](https://flake8.pycqa.org/) for linting
- Write type hints for all functions
- Add docstrings for all public functions and classes

#### Frontend (Flutter/Dart)
- Follow [Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- Use `dart format` for code formatting
- Use `flutter analyze` for static analysis
- Follow Flutter best practices for widget composition

### Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
type(scope): description

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `perf`: A code change that improves performance
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to the build process or auxiliary tools

**Examples:**
```
feat(auth): add JWT token refresh functionality
fix(upload): resolve S3 upload timeout issue
docs(api): update API documentation for new endpoints
```

### Testing

#### Backend Testing
```bash
cd backend
pytest tests/ -v --cov=app
```

#### Frontend Testing
```bash
flutter test
flutter integration_test
```

### Pull Request Process

1. **Update Documentation**: Update README.md and other relevant documentation
2. **Add Tests**: Add tests for new functionality
3. **Update CHANGELOG**: Document your changes
4. **Ensure CI Passes**: All tests must pass
5. **Request Review**: Request review from maintainers

## 🏗️ Project Structure

```
photoshare/
├── lib/                    # Flutter frontend
│   ├── screens/           # UI screens
│   ├── services/          # API services
│   ├── models/            # Data models
│   ├── widgets/           # Reusable widgets
│   └── utils/             # Utilities
├── backend/               # FastAPI backend
│   ├── app/
│   │   ├── api/           # API endpoints
│   │   ├── core/          # Core functionality
│   │   ├── models/        # Database models
│   │   ├── services/      # Business logic
│   │   └── utils/         # Utilities
│   └── tests/             # Backend tests
├── docs/                  # Documentation
└── test/                  # Frontend tests
```

## 🧪 Setting Up Development Environment

### Prerequisites
- Flutter SDK (>=3.2.3)
- Python (>=3.11)
- Git
- AWS Account (for testing)

### Backend Setup
```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your configuration
uvicorn app.main:app --reload
```

### Frontend Setup
```bash
flutter pub get
cp .env.example .env
# Edit .env with your configuration
flutter run
```

## 🐛 Bug Reports

When reporting bugs, please include:

1. **Environment**: OS, Flutter version, Python version
2. **Steps to Reproduce**: Clear, numbered steps
3. **Expected Behavior**: What should happen
4. **Actual Behavior**: What actually happens
5. **Screenshots**: If applicable
6. **Logs**: Relevant error messages or logs

## 💡 Feature Requests

When suggesting features:

1. **Use Case**: Describe the problem you're trying to solve
2. **Proposed Solution**: How you think it should work
3. **Alternatives**: Other solutions you've considered
4. **Additional Context**: Any other relevant information

## 📚 Documentation

Help us improve documentation by:

- Fixing typos and grammatical errors
- Adding code examples
- Improving explanations
- Adding missing information
- Translating to other languages

## 🏷️ Labels

We use the following labels for issues and PRs:

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to documentation
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `question`: Further information is requested
- `wontfix`: This will not be worked on

## 📞 Getting Help

- **GitHub Issues**: For bug reports and feature requests
- **GitHub Discussions**: For questions and general discussion
- **Email**: support@photoshare.app

## 🎉 Recognition

Contributors will be recognized in:
- README.md contributors section
- Release notes
- Project documentation

## 📄 License

By contributing to PhotoShare, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to PhotoShare! 🚀
