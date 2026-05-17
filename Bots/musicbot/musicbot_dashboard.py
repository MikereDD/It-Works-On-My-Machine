#!/usr/bin/env python3
def playlists():
    playlists_data = load_playlists()

    rows = []

    for item in sorted(
        playlists_data.values(),
        key=lambda x: x.get("imported", 0),
        reverse=True,
    ):
        rows.append(f"""
        <tr>
            <td>{item.get('url', '')}</td>
            <td>{item.get('total', 0)}</td>
            <td>{item.get('queued', 0)}</td>
            <td>{item.get('syncs', 0)}</td>
            <td>{item.get('mode', 'import')}</td>
        </tr>
        """)

    content = f"""
    <h1>🎵 Playlists</h1>

    <table>
        <tr>
            <th>Playlist</th>
            <th>Total</th>
            <th>Queued</th>
            <th>Syncs</th>
            <th>Mode</th>
        </tr>

        {''.join(rows)}
    </table>
    """

    return render_template_string(BASE_TEMPLATE, title="Playlists", content=content)


# ── Failed ───────────────────────────────────────────────────
@app.route("/failed")
def failed():
    failed_data = load_failed()

    rows = []

    for item in sorted(
        failed_data.values(),
        key=lambda x: x.get("last_failed", 0),
        reverse=True,
    ):
        rows.append(f"""
        <tr>
            <td>{item.get('query', '')}</td>
            <td>{item.get('reason', '')}</td>
            <td>{item.get('attempts', 0)}</td>
        </tr>
        """)

    content = f"""
    <h1>❌ Failed Queue</h1>

    <table>
        <tr>
            <th>Query</th>
            <th>Reason</th>
            <th>Attempts</th>
        </tr>

        {''.join(rows)}
    </table>
    """

    return render_template_string(BASE_TEMPLATE, title="Failed", content=content)


# ── JSON API ─────────────────────────────────────────────────
@app.route("/stats.json")
def stats_json():
    return jsonify(dashboard_stats())


@app.route("/library.json")
def library_json():
    return jsonify(load_library())


@app.route("/playlists.json")
def playlists_json():
    return jsonify(load_playlists())


@app.route("/failed.json")
def failed_json():
    return jsonify(load_failed())


# ── Main ─────────────────────────────────────────────────────
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8181, debug=False)