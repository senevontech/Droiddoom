change the updates:
godot_console --headless --path game --export-release "web" ../build/web/index.html
Copy-Item build\web\* ..\droidoom-deploy\ -Recurse -Force
git -C ..\droidoom-deploy add -A
git -C ..\droidoom-deploy commit --amend -m "chore: web build"
git -C ..\droidoom-deploy push --force second web-deploy
