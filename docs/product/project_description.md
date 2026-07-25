# LC Connect — Project Description

## 1. Project Name

**LC Connect**

Alternative names:

- BlueBridge
- CampusBridge
- Livingstone Connect
- The Yard Connect

The name can change later, but the MVP documentation will use **LC Connect**.

## 2. One-Sentence Description

LC Connect is a mobile-first, student-only campus app that helps Livingstone College students find friends, study partners, language exchange partners, campus activities, and respectful open connections through safe mutual matching.

## 3. Detailed Description

LC Connect is designed to solve a common campus problem: students often want to connect with each other, but they do not know how to start. This can happen between international students and domestic students, shy students and outgoing students, new students and older students, or students from different majors and social groups.

The app creates a safe digital bridge. Students can create a simple profile, choose what they are looking for, discover other students through interactive cards, send connection requests, and chat only when the connection is mutual. Students can also create or join campus activities, making it easier to meet in groups instead of relying only on one-on-one conversations.

The MVP should be simple, useful, and easy to understand. The goal is not to replace real-life campus interaction. The goal is to make real-life interaction easier to start.

## 4. Confirmed Product Direction

The confirmed direction is:

- Build a **real mobile app first**
- Use **Flutter + Riverpod** for the mobile frontend
- Use **FastAPI** for the backend API
- Use **PostgreSQL** for the database
- Use **Supabase** for Realtime message delivery and Row Level Security
- Start with a focused MVP, not a complicated full platform
- Make the app interactive through cards, prompts, activities, and mutual connections
- Include friendship, study partners, language exchange, events, and open connection
- Keep safety and student-only access as core principles

## 5. Why Mobile First

This app should be mobile-first because students are most likely to use it on their phones while on campus.

Students may check the app:

- Between classes
- In the cafeteria
- In the library
- In the dorm
- At campus events
- While planning study sessions
- While looking for people nearby or available

A normal website would be easier to build, but it would not match the behavior of students as well as a mobile app.

## 6. Core MVP Features

### 6.1 Student Signup and Login

Students should be able to create an account and log in securely.

MVP options:

- Email + password
- Student email verification if available
- Manual admin approval if needed

Recommended MVP approach:

- Start with email/password
- Add student verification flow
- Add admin review for suspicious accounts

### 6.2 Profile Setup

Each user creates a simple student profile.

Profile fields:

- Display name
- Profile photo
- Major
- Year/class level
- Country/state
- Bio
- Languages spoken
- Languages learning
- Interests
- Looking-for preferences

Looking-for options:

- Friendship
- Study partner
- Language exchange
- Events/activities
- Open connection

The profile should be short and friendly, not overwhelming.

### 6.3 Student Discovery Cards

The Connect screen should show student cards.

Each card should show:

- Name
- Photo
- Major/year
- Short bio
- Looking-for tags
- Interests
- Match reasons

Example match reasons:

- “You both like basketball.”
- “You are both interested in coding.”
- “They are also looking for a study partner.”
- “They speak Spanish and want to practice English.”

Actions on a card:

- Connect
- Study Together
- Invite to Activity
- Maybe Later
- Report/Block

### 6.4 Mutual Connection System

Messaging should only open after both students agree to connect.

Flow:

1. Student A sends a connection request to Student B.
2. Student B can accept or decline.
3. If accepted, a match is created.
4. Only matched students can message each other.

This reduces unwanted messages and awkwardness.

### 6.5 Basic Messaging

The MVP should include simple one-on-one messaging after a match.

Message features:

- Send text message
- View conversation history
- Basic timestamps
- Read status can come later
- Image/file sharing can come later

Do not overcomplicate chat in version 1.

### 6.6 Activity Board

The activity board is one of the most important features because it gives students a natural reason to meet.

Students can create activities such as:

- Library study session
- Basketball meetup
- Lunch meetup
- Coffee meetup
- Movie night
- Game night
- Campus walk
- International food night
- Language practice meetup
- Club event

Activity fields:

- Title
- Description
- Category
- Location
- Date/time
- Max people
- Created by
- Join button

### 6.7 Study Partner Matching

Students should be able to find study partners by:

- Major
- Course/class
- Subject
- Availability
- Study style

For MVP, keep it simple:

- Students can tag themselves as looking for a study partner
- Students can create study activities
- Discovery cards can show “Looking for study partner”

### 6.8 Language Exchange

Language exchange helps international and domestic students connect naturally.

Students can list:

- Languages they speak
- Languages they want to practice

Example:

- Student A speaks English and wants Spanish
- Student B speaks Spanish and wants English
- The app can show this as a strong match reason

### 6.9 Safety Features

Safety must be included from the beginning.

MVP safety features:

- Block user
- Report user
- Hide profile option
- Mutual connection before messaging
- Admin review of reports
- No public likes
- No public dating status required

### 6.10 Admin Review

The admin side can start very simple.

Admin should be able to:

- View users
- Review reports
- Suspend users
- Review activities
- Remove inappropriate activities
- Approve verification requests if needed

The admin panel can come after the mobile MVP, but the backend should be designed with admin needs in mind.

## 7. User Stories

### New Student

As a new student, I want to find people with similar interests so that I can make friends on campus.

### International Student

As an international student, I want to find language exchange partners so that I can practice English and meet domestic students.

### Domestic Student

As a domestic student, I want to meet international students and learn about different cultures without feeling awkward.

### Student Looking for Study Partner

As a student, I want to find someone in my major or course so that we can study together.

### Student Looking for Activities

As a student, I want to see what activities are happening so that I can join and meet people in person.

### Safety-Conscious Student

As a student, I want to block or report someone so that I feel safe using the app.

## 8. Design Feel

The app should feel:

- Friendly
- Clean
- Campus-centered
- Safe
- Interactive
- Modern
- Simple
- Not too formal
- Not too childish
- Not dating-first

Recommended UI style:

- Card-based discovery
- Rounded corners
- Soft shadows
- Clear tags
- Blue/white school-inspired colors
- Friendly empty states
- Small icebreaker prompts
- Simple activity cards

## 9. Icebreaker Ideas

The app can suggest simple prompts to help students start conversations.

Examples:

- “What’s your favorite place on campus?”
- “What class are you taking this semester?”
- “Want to study sometime this week?”
- “What music do you usually listen to?”
- “Are you going to any campus events this week?”
- “What’s one thing you like about Livingstone?”

These can be added in messages later, but the backend can support them as static prompts in version 1.

## 10. MVP Boundaries

The MVP should avoid:

- Too many profile fields
- Public feed
- Public comments
- Complicated dating features
- Full AI recommendation engine
- Complex real-time chat infrastructure
- Too many user roles
- Payment features
- Large event management tools

Start small. Prove that students want it. Then expand.
