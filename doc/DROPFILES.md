# DROPFILES
`dropfiles` is an exported archive of my personal `dotfiles` repository. Since
`dotfiles` contains all of my personal preferences in the form of configuration
files (as well as `gitconfig`s that store my full name and personal email
address), that stuff needs to be redacted from the project before distributing
it. Specifically, this is done via `git-archive(1)` and attributes on the files
that are to be ignored. The resulting archive is expanded into the `dropfiles`
repository, and a commit is generated from those changes.

I still have to remember to sync removed files by hand, but as long as I
remember, to do that, consumers of `dropfiles` can just clone the repository
into their home directory via a bare repository and get a snapshot of the
generically useful bits of `dotfiles`.

## Cloning
If you're not familiar with cloning a bare repository into your home directory,
there are several descriptions of the workflow you can find online, e.g.
[this one](https://coffeeaddict.dev/how-to-manage-dotfiles-with-git-bare-repo)
or [this one](https://www.atlassian.com/git/tutorials/dotfiles). But the gist of
how you'd use this workflow with `dropfiles` is...

1. `git clone --bare $REPOSITORY_URL $HOME/.dotfiles`
2. `git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout`
3. `git --git-dir=$HOME/.dotfiles --work-tree=$HOME config status.showUntrackedFiles no`

Tutorials will recommend creating an alias for the
`git --git-dir=$HOME/.dotfiles --work-tree=$HOME` bits of these commands, and
that's fine. But `dotfiles` has a `git-dotfiles` command that does that for you,
if you'd like to use that instead. Note that you'll have to ensure that
`$HOME/bin` is in your `PATH`.

## Employer-Specific Stuff
If you're cloning `dropfiles`, chances are you're a coworker who wants to use
some of my employer-specific tooling, since it will rely on the more generic
libraries in `dotfiles`. You can do the same dance for that repo and clone it
straight into your home directory, and it will safely co-locate with your
`dropfiles` working tree. Remember, `git` doesn't really know about directories;
it only cares about files. So you can have two repository working trees checked
out at the same root provided they don't have any conflicting files, which these
two repositories won't. So you can do...

1. `git clone --bare $REPOSITORY_URL $HOME/.dotemployer`
2. `git --git-dir=$HOME/.dotemployer --work-tree=$HOME checkout`
3. `git --git-dir=$HOME/.dotemployer --work-tree=$HOME config status.showUntrackedFiles no`

## Configuring `git-fix`
The `git-fix` utility needs a bit of git configuration that you can provide by
looking at ~/.dotgit/gitconfig_template` and filling in the relevant fields.
That file has comments describing each one's purpose.

Once you do that, you should be good to go.
