# MANA OORU — Team & AI Prompt Collaboration Guide

This guide is designed for **Rahul and his two teammates** to collaborate smoothly on Mana Ooru. 
Even if your friends have **never used Git, terminals, or coding tools before and only use AI prompts**, this workflow ensures nobody breaks the game or overwrites each other's work.

---

## 1. How the Setup Works

Instead of learning Git commands, **your friends' AI coding assistants (Antigravity, Cursor, Claude Code, etc.) will manage Git automatically**.

Because the repository has strict instructions in `AGENTS.md`, any AI assistant opening this project is forced to follow safe collaboration rules:
1. It will always sync the latest changes first.
2. It will create an isolated feature branch so it never accidentally damages `main`.
3. It will run Godot regression tests before saving.
4. It will create a clean Pull Request for review.

---

## 2. Step 1: Add Your Friends to the GitHub Repository

Your friends need permission to upload their work to your repository:

1. Open your repository: **[https://github.com/rahulpannatipubg9-creator/ManaOoru](https://github.com/rahulpannatipubg9-creator/ManaOoru)**
2. Click **Settings** (top tab).
3. In the left sidebar, click **Collaborators** (under "Access").
4. Click the green button: **Add people**.
5. Enter your friend's GitHub username or email address.
6. Click **Add to this repository**.
7. Your friend will receive an invitation email. They just need to open the email and click **Accept Invitation**.

*(Repeat for both friends).*

---

## 3. Step 2: Friend's First-Time Setup (One Prompt)

When your friends open their AI coding assistant on their computer, they only need to give this single prompt:

> **Friend's Setup Prompt:**
> *"Clone https://github.com/rahulpannatipubg9-creator/ManaOoru.git to my machine, run `./tools/setup_team.sh` to configure safety hooks, and run the movement regression tests to ensure the game works."*

Their AI will clone the project, activate the Git safety hooks, check Godot, and verify that everything runs!

---

## 4. The 3 "Magic Prompts" for Daily Work (Automated)

Your friends only need to copy and paste these 3 prompts whenever they work:

### 🟢 Prompt 1: When starting to build something new
> *"Run `./tools/sync.sh` to get the latest team updates, then create a new feature branch called 'feature/[what I want to build]', and inspect the existing code before changing anything."*
>
> *(Example: "Run ./tools/sync.sh, create a branch called feature/tea-stall-quest, and add a dialogue interaction with the tea vendor.")*

### 🟡 Prompt 2: When testing and uploading their work
> *"Run `./tools/ship.sh 'Add tea stall interaction'` to test everything, commit, and push my branch to GitHub for Rahul to review."*
>
> *(The script will automatically run Godot tests. If tests pass, it pushes to GitHub and prints the Pull Request link. If tests fail, it blocks the push and shows the error!)*

### 🔵 Prompt 3: When updating with the team's latest code
> *"Run `./tools/sync.sh` to safely pull the latest updates from main without losing any of my local work."*

---

## 5. Golden Rules to Prevent Conflicts in Godot

Godot `.tscn` (scene) files are text files. If two people modify the same scene (like `main.tscn`) at the exact same time, Git will produce a "merge conflict" that is confusing for beginners.

Follow these 3 simple rules:

1. **Work in Separate Sub-scenes:**
   - Friend A working on a new car? Create `scenes/vehicles/my_new_vehicle.tscn`.
   - Friend B working on a new UI menu? Create `scenes/ui/my_new_menu.tscn`.
   - Never edit `scenes/main.tscn` directly unless discussing it first.
2. **Assign Distinct Modules:**
   - **Rahul:** World map, Godavari Bridge, city roads, core player movement.
   - **Friend 1:** Missions, NPCs, dialogue, audio & sound design.
   - **Friend 2:** New vehicles, weapons, mini-games, UI polish.
3. **One Feature per Branch:**
   - Keep tasks small and focused. Finish one task, push it, merge it, then start the next.

---

## 6. How Rahul Reviews and Merges on GitHub

When a friend pushes their branch:

1. A notification banner will appear on GitHub: **`Compare & pull request`**.
2. Click **Create pull request**.
3. GitHub will check that there are no conflicts.
4. Rahul clicks the green **Merge pull request** button -> **Confirm merge**.
5. Done! The friend's new feature is now officially part of the game!
