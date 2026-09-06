# Simple Universal Linux Steam Downgrader

A small bash script to automate downgrading steam games to specific previous versions. 

Uses steam depots method, and downloads using steamCMD. The script can be configured for any steam game and any version using depot ids and manifest ids found on steamDB and be released for users. It supports choosing from multiple available old versions and can downgrade from any current version.

### Design Philosophy
- This project is intentionally small
- Only the core features to downgrade steam games but without compromising safety
- Download the files from steam to reduce chance of error and get data from Valve's trusted content delivery infrastructure
    - This does mean a somewhat lengthy download process for large games
- Backups made automatically
- Script will fully cleanup its files after running leaving only backups, which can be removed easily

### How to use
1. Open terminal at the location of the script
2. Run ./downgrader.sh
3. You will be prompted to continue and to authenticate steamCMD

Run `./downgrader.sh --restore-backup` to restore from backups \
And `./downgrader.sh --remove-backup` to remove backups and reclaim file space


### Why can you trust me with steam files and account
- You shouldn't, check the code. It's pretty short and all one bash file, no binary diff files or anything
- Authentication and downloads all handled by steamCMD: Valve's official command-line Steam client
- Makes backups before destructive operations

### How it works
1. Find steam libraries and the installed game by reading steam's libraryfolders.vdf
2. Download steamCMD from Valve and verify checksum
3. Authenticate and download files using included app id, depot ids and manifest ids
4. Make game installation backup
5. Merge depots and move to game folder, so it can be launched from steam as normal

### To configure for other games
The script is designed to be reusable for other Steam games.
Only the `Game Specific Variables` at the top of the file needs to be changed. The required depots can be found by inspecting the games `appmanifest_*.acf file in the steamapps folder, often multiple are needed. The manifest ids are unique for each game version and each correspond to a depot_id. All needed values can be found on [steamDB](https://steamdb.info/). You might also want to rename it to include the game name.

Example configurations are in games_info.txt.

To support multiple downgrade versions add multiple versions entries for versions, notes, and manifests like the skyrim example.

I give permission to upload this script configured for a game that I have not configured for to modding websites. If you do this, please test the configuration thoroughly and inform me through github.