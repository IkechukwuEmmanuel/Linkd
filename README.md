# Linkd

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Flutter](https://img.shields.io/badge/Frontend-Flutter_Dart-02569B)
![Python](https://img.shields.io/badge/Backend-Python-blue)
![Platform](https://img.shields.io/badge/Platform-Mobile-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## About

Linkd is an AI-powered relationship intelligence app that helps people remember and grow their professional network.

After meeting someone, users can record a short voice note about the conversation. Linkd processes the audio, extracts key information such as names, interests, and opportunities, and generates a structured relationship profile.

The system also compares the information from new contacts with the user’s own interests and goals, identifying shared topics and suggesting meaningful follow-ups.

Instead of scattered notes and forgotten conversations, Linkd builds a searchable memory of your network and helps turn introductions into lasting relationships.

---

## Visuals

*(Insert a GIF or screenshots of the mobile app here — ideally showing the capture screen and relationship profile view.)*

---

## Core Features

### Voice-Based Capture
Quickly record short voice notes after meeting someone. Linkd transcribes the audio and extracts useful relationship data.

### AI Relationship Profiles
Automatically generate structured profiles including:

- Name  
- Company  
- Interests  
- Context of interaction  
- Potential opportunities  

### Personal Interest Matching
Linkd compares information from new contacts with the user’s personal interests and professional goals to identify meaningful connection points.

### Follow-Up Intelligence
The system suggests potential follow-up actions based on conversation context and shared interests.

### Searchable Network Memory
Instantly search your network by name, interest, company, or event.

---

## Architecture

Linkd is built using a modern full-stack architecture designed for scalability and mobile performance.

### Frontend
- Flutter  
- Dart  
- Cross-platform mobile support (iOS and Android)

### Backend
- Python  
- REST API services  
- AI processing and data extraction  

### Core System Flow

```
User
 ↓
Voice Capture
 ↓
Speech-to-Text Processing
 ↓
AI Entity Extraction
 ↓
Relationship Profile Generation
 ↓
Interest Matching Engine
 ↓
Searchable Network Database
 ↓
Follow-Up Intelligence
```

---

## Repository Structure

```
Linkd
│
├── lin/        # Flutter mobile application
│
├── ked/        # Python backend services
│
└── README.md
```

The repository follows a mono-repo architecture, allowing the mobile client and backend services to evolve independently while remaining tightly integrated.

---

## Prerequisites

Before running the project locally, ensure you have the following installed:

- Flutter SDK  
- Python 3.10+  
- pip  
- Android Emulator or iOS Simulator  

Run the following command to confirm Flutter is properly installed:

```
flutter doctor
```

---

## Installation

Because Linkd uses a mono-repo structure, you will need to configure both the backend and frontend.

### 1. Clone the Repository

```
git clone https://github.com/justicethinker/Linkd.git
cd Linkd
```

---

### 2. Setup the Backend

```
cd ked
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create a `.env` file with your configuration:

```
DATABASE_URL="your_db_connection_string"
SECRET_KEY="your_secret_key"
```

Return to the root directory:

```
cd ..
```

---

### 3. Setup the Mobile Client

```
cd lin
flutter pub get
```

---

## Usage

### Running the Backend

```
cd ked
source venv/bin/activate
uvicorn main:app --reload
```

*(Replace the command with your backend entry point if different.)*

---

### Running the Mobile Client

Open another terminal and run:

```
cd lin
flutter run
```

This will launch the app on your connected device or emulator.

---

## Contributing

Contributions are welcome.

1. Fork the repository  
2. Create a feature branch  

```
git checkout -b feature/new-feature
```

3. Commit your changes  

```
git commit -m "Add new feature"
```

4. Push to the branch  

```
git push origin feature/new-feature
```

5. Open a Pull Request  

---

## License

Distributed under the **MIT License**.  
See the `LICENSE` file for more information.

---

## Contact

Justice Thinker  
justicethinker2@gmail.com  

GitHub:  
https://github.com/justicethinker
