# Building dynflow.github.io

1. Clone the `dynflow.github.io` to the public directory

```
git clone github.com:dynflow/dynflow.github.io public --origin upstream
```

2. Add your fork

```
cd public
git remote add origin github.com:$MYUSERNAME/dynflow.github.io
cd ..
```

2. Install the dependencies

```
bundle install
```

3. Make sure the public repository is in sync with upstream

```
cd public
git fetch upstream master
git reset --hard upstream/master
git clean -f
cd ..
```

4. Build new version of the pages

```
bundle exec jekyll build
```

5. Commit and push the updated version

```
cd public
git add -A
git commit -m Update
git push origin master
```

6. Send us a PR
