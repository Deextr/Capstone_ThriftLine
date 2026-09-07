# Capstone ThriftLine Agent Guidelines (`AGENTS.md`)

This document outlines the architectural patterns, directory structure, coding standards, and guidelines for the Capstone ThriftLine project. All agents and development assistants must strictly adhere to these practices when adding features, refactoring code, or debugging.

---

## 1. Project Architecture (Feature-First MVC)

ThriftLine is structured using a **Feature-First MVC (Model-View-Controller)** pattern. This isolates features into distinct, self-contained directories while using a clean separation between UI/presentation components and state/business logic.

### Directory Structure

All application code resides under the `lib/` directory:

```
lib/
├── app/               # App-wide widgets, setup, and entry points
├── core/              # Global infrastructure and cross-cutting concerns
│   ├── config/        # app configurations
│   ├── constants/     # Global constant definitions (colors, dimensions, etc.)
│   ├── data/          # App-wide data helpers/local database services
│   |                    this only has mock use for prototype(cacche memory to show the ui interactions)
│   ├── routes/        # Router configuration (using GoRouter) and route names
│   ├── services/      # Long-running services (SupabaseService, SharedPreferencesService)
│   ├── theme/         # App theme, colors, typography (using Google Fonts)
│   └── utils/         # Global utilities and helper functions
├── features/          # Self-contained modules organized by domain/feature
│   ├── auth/          # Authentication & user sessions
│   ├── buyer/         # Buyer flows (search, bidding, checkout, purchase history)
│   ├── seller/        # Seller flows (add listing, edit listing, dashboard)
│   ├── chat/          # Real-time buyer-seller messaging
│   ├── notifications/ # Push & in-app notifications
│   ├── profile/       # User profile management
│   ├── settings/      # Application settings
│   └── trust_safety/  # Dispute resolution, escrow tracking, reviews
├── models/            # Global database models and enums mapping Supabase tables
├── providers/         # Global state providers (e.g., AuthProvider)
└── widgets/           # Reusable global UI widgets (ThriftWidgets)
├── .env               # Environment variables
```

---

## 2. Component Separation & Responsibilities

Within each feature in `lib/features/<feature_name>/`, follow this structure:

### 2.1 Controllers (`/controllers/`)
* **Role**: Act as the Controller in MVC. Owns all UI state, form validation, Supabase database queries, device plugin interaction (e.g. `ImagePicker`), and async flow management.
* **Base Class**: Must extend `ChangeNotifier`.
* **State Updates**: Modify state variables and call `notifyListeners()` to trigger UI updates.
* **Dependencies**: Pass dependencies (such as `SupabaseService`, `AuthProvider`, or utility packages) into the constructor to enable clean unit testing.
* **Testing**: Expose helper functions and maps at package level (annotated with `@visibleForTesting`) where appropriate.

### 2.2 Presentation (`/presentation/`)
Divided into two subdirectories:
* **Screens (`/presentation/screens/`)**:
  * **Role**: Pure UI wrappers.
  * **State Reading**: Read/watch controller state via `context.watch<FeatureController>()`.
  * **Event Delegation**: Forward user interactions (button clicks, form submits) directly to the controller via `context.read<FeatureController>().someAction()`.
  * **Constraint**: Must *never* implement raw business logic, form validation logic, or direct Supabase API calls. Keep screens clean and representational.
* **Widgets (`/presentation/widgets/`)**:
  * **Role**: Small, specialized UI components layout out parts of the screen that are unique to this feature.

---

## 3. State Management & Dependency Injection

We use the `provider` package for state management.

1. **Injection**: Controller instances must be injected at the route or screen entry level using a `ChangeNotifierProvider`:
   ```dart
   ChangeNotifierProvider(
     create: (context) => AddListingController(
       supabase: context.read<SupabaseService>(),
       auth: context.read<AuthProvider>(),
     ),
     child: const AddListingScreen(),
   )
   ```
2. **Accessing State**:
   * Use `context.watch<MyController>()` inside the `build` method of widgets that need to rebuild when state changes.
   * Use `context.read<MyController>()` inside callbacks and event handlers (e.g. `onPressed`) to trigger methods without subscribing to rebuilds.

---

## 4. Supabase Schema & Database Guidelines

ThriftLine uses **Supabase** for database, storage, and authentication services.

* Refer to the database definitions in [supabase.txt](file:///c:/Users/user/projects/Capstone_ThriftLine/supabase.txt) for exact table designs.

## 5. Coding & Style Conventions

1. **Linting**: Follow the standard rules specified in [analysis_options.yaml](file:///c:/Users/user/projects/Capstone_ThriftLine/analysis_options.yaml). Ensure all files pass code analysis.
2. **Formatting**: Format all Dart code using the standard `dart format`.
3. **Route Management**: Use the global router configuration (GoRouter). Define route names in [route_names.dart](file:///c:/Users/user/projects/Capstone_ThriftLine/lib/core/routes/route_names.dart) and reference them for all navigation tasks.
4. **Error Handling**: Implement user-friendly error banners or dialogs. Wrap network and Supabase transactions in `try-catch` blocks within controllers and expose error state variables for screens to render.
5. **Loading States**: Manage asynchronous progress flags (e.g. `isLoading`) in the controller to display loading spinners or shimmers (`shimmer` package) in screens.
