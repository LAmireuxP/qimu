(() => {
  "use strict";

  const LANG_KEY = "bootanim_lang";

  const LANGUAGES = {
    "en": {
      name: "English",
      nativeName: "English"
    },
    "id": {
      name: "Indonesian",
      nativeName: "Bahasa Indonesia"
    },
    "zh-CN": {
      name: "Chinese Simplified",
      nativeName: "简体中文"
    }
  };

  const TRANSLATIONS = {
    "en": {
      // App header
      app_title: "Boot Animation Manager",
      app_sub: "Change boot animation, takes effect after reboot",
      theme_group_aria: "Theme style",
      theme_auto: "System",
      theme_light: "Light",
      theme_dark: "Dark",
      lang_btn_aria: "Select Language",
      lang_modal_title: "Select Language",
      lang_active_tag: "Active",
      theme_modal_title: "Theme Style",
      theme_desc_auto: "Follow device system appearance",
      theme_desc_light: "Light theme",
      theme_desc_dark: "Dark theme",
      toast_theme_changed: "Theme changed to {theme}",

      // Current Animation Card
      cur_title: "Current Animation",
      cur_loading: "Loading…",
      cur_none: "None",
      cur_noanim: "Boot animation disabled: boots directly to system (animations remain in library)",
      cur_theme_ok: "Written to theme path, takes effect after reboot · {size}",
      cur_not_written: "Not written yet, will be written when switching animation",
      cur_path_lib: "Library file: {path}",
      cur_path_theme: "Deploy path: {path}",
      cur_path_screen: "Device screen: {screen}",

      // Library Card
      lib_title: "Animation Library",
      lib_meta: "{count} items · {size}",
      lib_empty: "Animation library is empty",
      lib_load_failed: "Failed to load, click \"Refresh\" to retry",
      lib_hint: "Click \"Apply\" to switch animation, reboot to take effect; the active one cannot be deleted.<br>Click <b>▶</b> to preview first, no reboot or applying needed.<br>Reorder: hold <b>⠿</b> on the left to drag, or use <b>▲▼</b> to move step by step.<br>Selecting \"Disable Animation\" shows a black screen on boot and goes straight to system.",
      drag_handle_title: "Hold and drag to reorder",
      preview_btn_title: "Preview (no reboot needed)",
      move_up_title: "Move up",
      move_down_title: "Move down",
      in_use_tag: "In Use",
      btn_apply: "Apply",
      btn_applied: "Applied",
      btn_edit: "Edit",
      btn_delete: "Delete",
      btn_confirm_delete: "Confirm delete?",

      // Toolbar
      btn_refresh: "Refresh",
      btn_check: "Check",
      btn_browse: "Choose File",
      btn_collapse_list: "Collapse List",
      btn_vid: "Convert Video",

      // File Browser Card
      browse_title: "Choose File",
      browse_parent_dir: "⬆ Parent Directory",
      browse_folder: "Folder",
      browse_vid_sub: "{size} · Video convertible to boot animation",
      browse_btn_convert: "Convert",
      browse_btn_import: "Import",
      browse_empty: "No subfolders or zip files in this directory",
      browse_hint: "Click folders to browse, find an animation zip and click \"Import\" on the right.<br>To change directory use \"⬆ Parent Directory\" on top; click \"Choose File\" again to collapse, and clicking again starts from \"Download\".",

      // Edit Modal
      res_modal_title: "Edit Animation · ",
      res_name_placeholder: "Animation name",
      btn_rename: "Rename",
      res_hint: "Modifies desc.txt in this library copy; currently active animation will be automatically redeployed.",
      btn_fit_screen: "Fit to Screen",
      btn_swap: "Swap W/H",
      btn_export: "Export",
      res_custom_title: "Custom Resolution",
      res_custom_sub: "Keep original frame rate, only change width and height",
      res_w_placeholder: "Width",
      res_h_placeholder: "Height",
      btn_res_apply: "Apply",
      btn_close: "Close",
      res_reading: "Loading…",
      res_cur_res: "Current resolution: ",
      res_unknown: "Unknown",
      res_adapt_mode: "Adaptation mode: ",
      res_mode_manual: "Manual (no longer auto-adapted on deployment, click \"Fit to Screen\" to restore)",
      res_mode_auto: "Auto (adapted to screen on deployment)",
      res_frames: "Frames: {frames} frames",
      res_dur: "Duration ~{dur}",
      res_screen: "Device screen: {screen}",

      // Preview Modal
      pv_close_aria: "Close preview",
      pv_preparing: "Preparing…",
      pv_replay: "Replay",
      pv_extracting: "Extracting frames…",
      pv_loading_frame: "Loading frame {current}/{total}…",
      pv_stride_note: " (1 every {stride} frames)",
      pv_part_seg: "Part {si}/{count}",
      pv_loop_infinite: "Infinite loop",
      pv_loop_times: "Loop {rep}/{loop}",
      pv_noanim_note: " · Boots directly to system",
      pv_no_playable_frames: "This package has no playable frames",
      pv_failed: "Preview failed",

      // Video to Animation Card
      vid_title: "Video to Animation",
      vid_searching: "Searching for videos…",
      vid_reading_dir: "Reading directory…",
      vid_browse_other: "📁 Browse Other Directories",
      vid_browse_other_sub: "Browse folders to find videos",
      vid_btn_browse: "Browse",
      vid_btn_select: "Select",
      vid_btn_open: "Open",
      vid_empty_dir: "No videos or subfolders in this directory",
      vid_fps_label: "Frame Rate",
      vid_fps_sub: "Sampling rate, default 30 (high frame rate strains decoding)",
      vid_play_label: "Playback Mode",
      vid_play_sub: "Auto = short video loops until system boot",
      vid_loop_auto: "Auto",
      vid_loop_loop: "Loop",
      vid_loop_once: "Play Once",
      vid_quality_label: "Quality",
      vid_quality_sub: "Standard = smaller size, faster conversion",
      vid_quality_high: "High Quality",
      vid_quality_standard: "Standard",
      vid_btn_start: "Start Conversion & Import",
      vid_hint: "Select a video (lists \"Download\" and \"Movies\" by default) to convert into an animation package and auto-import into the library;<br>For other directories click \"Browse Other Directories\". Quality: full-screen native resolution, high-quality JPG;<br>Maximum 600 frames, trimming long videos beforehand is recommended; video only, no audio.<br>Format must be browser-decodable: MP4/H.264 is most reliable.<br>Click \"Convert Video\" again to collapse, clicking again returns to the last viewed directory.",

      // Dynamic Video Conversion messages
      vid_prog_reading: "Reading video {percent}%",
      vid_prog_detail: "Video {vw}×{vh} {dur}s → {n} frames {fps}fps{loop}",
      vid_loop_tag: " (loop)",
      vid_once_tag: " (once)",
      vid_prog_extracting: "Extracting frames {i}/{n}",
      vid_prog_packing: "Packing zip…",
      vid_prog_writing: "Writing back {percent}%",
      vid_prog_importing: "Importing to animation library…",
      vid_prog_done: "Import complete",
      vid_default_name: "Video to Animation",

      // Built-in special animation names
      no_anim_name: "Disable Animation",
      demo_anim_name: "Demo Animation",

      // Units
      bytes_unknown: "Unknown size",

      // Toasts & Success/Info messages
      toast_order_saved: "Order saved",
      toast_switched: "Switched to {name}, takes effect after reboot",
      toast_deleted: "Deleted {name}",
      toast_imported: "Imported {name}",
      toast_exported: "Exported to {path}",
      toast_name_empty: "Name cannot be empty",
      toast_name_too_long: "Name must be 60 characters or fewer",
      toast_renamed: "Renamed to {name}",
      toast_adapted: "Adapted to device screen",
      toast_swapped: "Width and height swapped",
      toast_num_required: "Width and height must be numbers",
      toast_num_range: "Width and height must be between 100 and 16384",
      toast_res_set: "Set to {w}×{h}",
      toast_check_ok: "Health check passed: all {count} packages can play normally",
      toast_check_bad: "{count} package(s) have issues, e.g. {detail}",
      toast_check_bad_simple: "{count} package(s) have issues",
      toast_pick_video: "Select a video first",
      toast_convert_done: "Conversion complete: {frames} frames at {fps}fps, imported {stored}, takes effect after reboot",
      toast_lang_changed: "Language changed to English",

      // Client-side Errors & Fallbacks
      err_op_failed: "Operation failed, please try again",
      err_op_failed_simple: "Operation failed",
      err_no_ksu_list: "KernelSU module interface not detected, unable to read animation list",
      err_no_ksu_root: "KernelSU / SukiSU module interface not detected. Please open this page in the module manager.",
      err_cmd_timeout: "Command execution timed out",
      err_dir_read_failed: "Failed to read directory",
      err_cannot_read_video: "Cannot read video content",
      err_video_too_large: "Video too large ({size}MB > {limit}MB), trim it before converting",
      err_video_incomplete: "Video read incomplete, please try again",
      err_write_verify_failed: "Write verification failed ({sz} ≠ {len})",
      err_video_not_supported: "Browser cannot decode this video (MP4/H.264 recommended, try converting other formats to MP4)",
      err_video_read_timeout: "Reading video timed out",
      err_video_invalid_info: "Abnormal video information",
      err_no_frames_extracted: "No video frames extracted, aborted: decoding issue, try another MP4",
      err_frame_timeout: "Frame loading timed out",
      err_frame_read_failed: "Cannot read frame",

      // Backend ctl.sh Error Mappings
      err_anim_not_found: "Animation not found, please refresh and try again",
      err_file_not_found: "File not found, may have been moved or deleted",
      err_file_empty_or_missing: "File does not exist or is empty",
      err_not_valid_zip: "Not a valid zip file",
      err_missing_desc: "Missing desc.txt in zip root",
      err_desc_empty: "desc.txt is empty",
      err_desc_bom: "desc.txt contains UTF-8 BOM which causes black screen on boot - please save as UTF-8 without BOM",
      err_desc_not_standard: "First line of desc.txt is not in \"width height fps\" format",
      err_no_frames: "No frame images in package (only desc.txt, will cause black screen on boot)",
      err_bad_parts: "Part directory in desc does not exist or has no frames: {badpart} (will cause black screen on boot)",
      err_zip_stored_required: "Animation must be in uncompressed ZIP_STORED format",
      err_cannot_read_desc: "Cannot read desc.txt",
      err_desc_format_invalid: "desc is not in standard format",
      err_write_desc_failed: "Failed to write desc",
      err_save_selection_failed: "Failed to save selection",
      err_write_theme_failed: "Animation selected, but failed to write to theme path",
      err_cannot_read_screen: "Cannot read device resolution",
      err_adapt_failed: "Adaptation failed: new resolution string is longer than original, or desc is not standard",
      err_w_must_be_num: "Width must be a number",
      err_h_must_be_num: "Height must be a number",
      err_digits_too_long: "Width/height digits too long",
      err_range_invalid: "Width/height out of valid range (100-16384)",
      err_name_empty: "Name cannot be empty",
      err_name_invalid: "Invalid name",
      err_name_dot_start: "Name cannot start with a dot (becomes hidden file, invisible in list)",
      err_name_duplicate: "Animation with the same name already exists",
      err_rename_failed: "Failed to rename",
      err_no_file_specified: "No file specified",
      err_copy_file_failed: "Failed to copy file",
      err_anim_in_use: "This animation is currently in use, please switch to another animation first",
      err_delete_failed: "Failed to delete",
      err_path_no_dots: "Path cannot contain ..: {path}",
      err_browse_not_allowed: "Browsing this path is not allowed: {path}",
      err_no_such_dir: "Directory does not exist: {path}",
      err_lib_empty: "Animation library is empty",
      err_reset_failed: "Reset failed",
      err_params_empty: "Empty arguments",
      err_write_order_failed: "Failed to write order",
      err_save_order_failed: "Failed to save order",
      err_target_is_source: "Target is the library file itself",
      err_write_failed: "Failed to write: {path}",
      err_no_unzip: "No unzip utility on device, cannot extract frames",
      err_cannot_read_zip_dir: "Cannot read package directory (zip may be corrupted)",
      err_no_desc_in_pkg: "Package has no desc.txt",
      err_no_parts_in_desc: "No p/c parts in desc",
      err_no_previewable_frames: "This package has no previewable frames",
      err_cannot_create_pv_dir: "Cannot create preview directory: {path}",
      err_cannot_decode_frames: "Cannot decode frames (images may not be PNG/JPG)",
      err_sync_deploy_failed: "Synchronization deployment failed"
    },
    "id": {
      // App header
      app_title: "Pengelola Animasi Boot",
      app_sub: "Ganti animasi boot, berlaku setelah reboot",
      theme_group_aria: "Gaya tema",
      theme_auto: "Sistem",
      theme_light: "Terang",
      theme_dark: "Gelap",
      lang_btn_aria: "Pilih Bahasa",
      lang_modal_title: "Pilih Bahasa",
      lang_active_tag: "Aktif",
      theme_modal_title: "Gaya Tema",
      theme_desc_auto: "Mengikuti tampilan sistem perangkat",
      theme_desc_light: "Tema terang",
      theme_desc_dark: "Tema gelap",
      toast_theme_changed: "Tema diubah ke {theme}",

      // Current Animation Card
      cur_title: "Animasi Saat Ini",
      cur_loading: "Memuat…",
      cur_none: "Tidak ada",
      cur_noanim: "Animasi boot dinonaktifkan: boot langsung ke sistem (animasi tetap ada di pustaka)",
      cur_theme_ok: "Ditulis ke jalur tema, berlaku setelah reboot · {size}",
      cur_not_written: "Belum ditulis, akan ditulis saat beralih animasi",
      cur_path_lib: "Berkas pustaka: {path}",
      cur_path_theme: "Jalur pemasangan: {path}",
      cur_path_screen: "Layar perangkat: {screen}",

      // Library Card
      lib_title: "Pustaka Animasi",
      lib_meta: "{count} item · {size}",
      lib_empty: "Pustaka animasi kosong",
      lib_load_failed: "Gagal memuat, klik \"Segarkan\" untuk mencoba lagi",
      lib_hint: "Klik \"Terapkan\" untuk mengganti animasi, berlaku setelah reboot; animasi aktif tidak dapat dihapus.<br>Klik <b>▶</b> untuk melihat pratinjau terlebih dahulu tanpa perlu reboot atau menerapkan.<br>Urutkan: tahan <b>⠿</b> di sebelah kiri untuk menyeret, atau gunakan <b>▲▼</b> untuk memindahkan satu per satu.<br>Memilih \"Tanpa Animasi\" akan menampilkan layar hitam saat boot dan langsung masuk sistem.",
      drag_handle_title: "Tahan dan seret untuk mengurutkan",
      preview_btn_title: "Pratinjau (tanpa perlu reboot)",
      move_up_title: "Pindah ke atas",
      move_down_title: "Pindah ke bawah",
      in_use_tag: "Digunakan",
      btn_apply: "Terapkan",
      btn_applied: "Diterapkan",
      btn_edit: "Edit",
      btn_delete: "Hapus",
      btn_confirm_delete: "Konfirmasi hapus?",

      // Toolbar
      btn_refresh: "Segarkan",
      btn_check: "Periksa",
      btn_browse: "Pilih Berkas",
      btn_collapse_list: "Tutup Daftar",
      btn_vid: "Konversi Video",

      // File Browser Card
      browse_title: "Pilih Berkas",
      browse_parent_dir: "⬆ Direktori Induk",
      browse_folder: "Folder",
      browse_vid_sub: "{size} · Video dapat dikonversi ke animasi boot",
      browse_btn_convert: "Konversi",
      browse_btn_import: "Impor",
      browse_empty: "Tidak ada subfolder atau berkas zip di direktori ini",
      browse_hint: "Klik folder untuk menjelajah, temukan zip animasi dan klik \"Impor\" di sebelah kanan.<br>Gunakan \"⬆ Direktori Induk\" di baris pertama untuk berpindah direktori; klik \"Pilih Berkas\" lagi untuk menutup, dan klik lagi untuk memulai kembali dari folder \"Download\".",

      // Edit Modal
      res_modal_title: "Edit Animasi · ",
      res_name_placeholder: "Nama animasi",
      btn_rename: "Ganti Nama",
      res_hint: "Mengubah desc.txt pada salinan pustaka ini; animasi yang sedang digunakan akan dipasang ulang secara otomatis.",
      btn_fit_screen: "Sesuaikan Layar",
      btn_swap: "Tukar P/L",
      btn_export: "Ekspor",
      res_custom_title: "Resolusi Kustom",
      res_custom_sub: "Pertahankan frame rate asli, hanya ubah lebar dan tinggi",
      res_w_placeholder: "Lebar",
      res_h_placeholder: "Tinggi",
      btn_res_apply: "Terapkan",
      btn_close: "Tutup",
      res_reading: "Memuat…",
      res_cur_res: "Resolusi saat ini: ",
      res_unknown: "Tidak diketahui",
      res_adapt_mode: "Mode adaptasi: ",
      res_mode_manual: "Manual (tidak lagi disesuaikan otomatis saat pemasangan, klik \"Sesuaikan Layar\" untuk memulihkan)",
      res_mode_auto: "Otomatis (disesuaikan dengan layar saat pemasangan)",
      res_frames: "Jumlah frame: {frames} frame",
      res_dur: "Durasi ~{dur}",
      res_screen: "Layar perangkat: {screen}",

      // Preview Modal
      pv_close_aria: "Tutup pratinjau",
      pv_preparing: "Menyiapkan…",
      pv_replay: "Putar Ulang",
      pv_extracting: "Mengekstrak frame…",
      pv_loading_frame: "Memuat frame {current}/{total}…",
      pv_stride_note: " (1 setiap {stride} frame)",
      pv_part_seg: "Bagian {si}/{count}",
      pv_loop_infinite: "Putar terus menerus",
      pv_loop_times: "Putaran ke-{rep}/{loop}",
      pv_noanim_note: " · Boot langsung ke sistem",
      pv_no_playable_frames: "Paket ini tidak memiliki frame yang dapat diputar",
      pv_failed: "Pratinjau gagal",

      // Video to Animation Card
      vid_title: "Video ke Animasi",
      vid_searching: "Mencari video…",
      vid_reading_dir: "Membaca direktori…",
      vid_browse_other: "📁 Jelajahi Direktori Lain",
      vid_browse_other_sub: "Jelajahi folder untuk menemukan video",
      vid_btn_browse: "Jelajah",
      vid_btn_select: "Pilih",
      vid_btn_open: "Buka",
      vid_empty_dir: "Tidak ada video atau subfolder di direktori ini",
      vid_fps_label: "Frame Rate",
      vid_fps_sub: "Laju sampling, default 30 (frame rate tinggi membebani dekoding)",
      vid_play_label: "Mode Pemutaran",
      vid_play_sub: "Otomatis = video pendek berulang sampai boot sistem selesai",
      vid_loop_auto: "Otomatis",
      vid_loop_loop: "Berulang",
      vid_loop_once: "Putar Sekali",
      vid_quality_label: "Kualitas",
      vid_quality_sub: "Standar = ukuran lebih kecil, konversi lebih cepat",
      vid_quality_high: "Kualitas Tinggi",
      vid_quality_standard: "Standar",
      vid_btn_start: "Mulai Konversi & Impor",
      vid_hint: "Pilih video (daftar default dari \"Download\" dan \"Movies\") untuk dikonversi menjadi paket animasi dan diimpor otomatis ke pustaka;<br>Untuk direktori lain, klik \"Jelajahi Direktori Lain\". Kualitas: layar penuh resolusi asli, JPG berkualitas tinggi;<br>Maksimal 600 frame, disarankan memotong video panjang terlebih dahulu; hanya gambar, tanpa suara.<br>Format harus dapat didekode oleh peramban: MP4/H.264 paling stabil.<br>Klik \"Konversi Video\" lagi untuk menutup, klik lagi untuk kembali ke direktori yang terakhir dilihat.",

      // Dynamic Video Conversion messages
      vid_prog_reading: "Membaca video {percent}%",
      vid_prog_detail: "Video {vw}×{vh} {dur}s → {n} frame {fps}fps{loop}",
      vid_loop_tag: " (berulang)",
      vid_once_tag: " (sekali)",
      vid_prog_extracting: "Mengekstrak frame {i}/{n}",
      vid_prog_packing: "Mengemas zip…",
      vid_prog_writing: "Menulis kembali {percent}%",
      vid_prog_importing: "Mengimpor ke pustaka animasi…",
      vid_prog_done: "Impor selesai",
      vid_default_name: "Video ke Animasi",

      // Built-in special animation names
      no_anim_name: "Tanpa Animasi",
      demo_anim_name: "Animasi Demo",

      // Units
      bytes_unknown: "Ukuran tidak diketahui",

      // Toasts & Success/Info messages
      toast_order_saved: "Urutan disimpan",
      toast_switched: "Beralih ke {name}, berlaku setelah reboot",
      toast_deleted: "Berhasil menghapus {name}",
      toast_imported: "Berhasil mengimpor {name}",
      toast_exported: "Diekspor ke {path}",
      toast_name_empty: "Nama tidak boleh kosong",
      toast_name_too_long: "Nama maksimal 60 karakter",
      toast_renamed: "Nama diubah menjadi {name}",
      toast_adapted: "Disesuaikan dengan layar perangkat",
      toast_swapped: "Lebar dan tinggi telah ditukar",
      toast_num_required: "Lebar dan tinggi harus berupa angka",
      toast_num_range: "Lebar dan tinggi harus antara 100 dan 16384",
      toast_res_set: "Diatur ke {w}×{h}",
      toast_check_ok: "Pemeriksaan kesehatan lolos: semua {count} paket dapat diputar normal",
      toast_check_bad: "{count} paket bermasalah, contoh {detail}",
      toast_check_bad_simple: "{count} paket bermasalah",
      toast_pick_video: "Pilih video terlebih dahulu",
      toast_convert_done: "Konversi selesai: {frames} frame pada {fps}fps, diimpor {stored}, berlaku setelah reboot",
      toast_lang_changed: "Bahasa diubah ke Bahasa Indonesia",

      // Client-side Errors & Fallbacks
      err_op_failed: "Operasi gagal, silakan coba lagi",
      err_op_failed_simple: "Operasi gagal",
      err_no_ksu_list: "Antarmuka modul KernelSU tidak terdeteksi, tidak dapat membaca daftar animasi",
      err_no_ksu_root: "Antarmuka modul KernelSU / SukiSU tidak terdeteksi. Silakan buka halaman ini di pengelola modul.",
      err_cmd_timeout: "Eksekusi perintah melebihi batas waktu",
      err_dir_read_failed: "Gagal membaca direktori",
      err_cannot_read_video: "Tidak dapat membaca konten video",
      err_video_too_large: "Video terlalu besar ({size}MB > {limit}MB), potong sebelum konversi",
      err_video_incomplete: "Pembacaan video tidak lengkap, silakan coba lagi",
      err_write_verify_failed: "Verifikasi penulisan gagal ({sz} ≠ {len})",
      err_video_not_supported: "Peramban tidak dapat mendekode video ini (MP4/H.264 direkomendasikan, coba konversi format lain ke MP4)",
      err_video_read_timeout: "Membaca video melebihi batas waktu",
      err_video_invalid_info: "Informasi video tidak normal",
      err_no_frames_extracted: "Tidak ada frame video yang diekstrak, dibatalkan: masalah decoding, coba MP4 lain",
      err_frame_timeout: "Pemuatan frame melebihi batas waktu",
      err_frame_read_failed: "Tidak dapat membaca frame",

      // Backend ctl.sh Error Mappings
      err_anim_not_found: "Animasi tidak ditemukan, silakan segarkan dan coba lagi",
      err_file_not_found: "Berkas tidak ditemukan, mungkin telah dipindah atau dihapus",
      err_file_empty_or_missing: "Berkas tidak ada atau kosong",
      err_not_valid_zip: "Bukan berkas zip yang valid",
      err_missing_desc: "desc.txt tidak ditemukan di root zip",
      err_desc_empty: "desc.txt kosong",
      err_desc_bom: "desc.txt mengandung BOM UTF-8 yang menyebabkan layar hitam saat boot - simpan ulang sebagai UTF-8 tanpa BOM",
      err_desc_not_standard: "Baris pertama desc.txt bukan format \"lebar tinggi fps\"",
      err_no_frames: "Tidak ada gambar frame dalam paket (hanya desc.txt, akan menyebabkan layar hitam saat boot)",
      err_bad_parts: "Direktori bagian dalam desc tidak ada atau tidak memiliki frame: {badpart} (akan menyebabkan layar hitam saat boot)",
      err_zip_stored_required: "Animasi harus berformat ZIP_STORED tanpa kompresi",
      err_cannot_read_desc: "Tidak dapat membaca desc.txt",
      err_desc_format_invalid: "desc bukan format standar",
      err_write_desc_failed: "Gagal menulis desc",
      err_save_selection_failed: "Gagal menyimpan pilihan",
      err_write_theme_failed: "Animasi dipilih, tetapi gagal menulis ke jalur tema",
      err_cannot_read_screen: "Tidak dapat membaca resolusi perangkat",
      err_adapt_failed: "Adaptasi gagal: string resolusi baru lebih panjang dari aslinya, atau desc bukan format standar",
      err_w_must_be_num: "Lebar harus berupa angka",
      err_h_must_be_num: "Tinggi harus berupa angka",
      err_digits_too_long: "Digit lebar/tinggi terlalu panjang",
      err_range_invalid: "Lebar/tinggi di luar batas wajar (100-16384)",
      err_name_empty: "Nama tidak boleh kosong",
      err_name_invalid: "Nama tidak valid",
      err_name_dot_start: "Nama tidak boleh dimulai dengan titik (menjadi berkas tersembunyi, tidak terlihat di daftar)",
      err_name_duplicate: "Animasi dengan nama yang sama sudah ada",
      err_rename_failed: "Gagal mengubah nama",
      err_no_file_specified: "Berkas tidak ditentukan",
      err_copy_file_failed: "Gagal menyalin berkas",
      err_anim_in_use: "Animasi ini sedang digunakan, silakan beralih ke animasi lain terlebih dahulu",
      err_delete_failed: "Gagal menghapus",
      err_path_no_dots: "Jalur tidak boleh mengandung ..: {path}",
      err_browse_not_allowed: "Jalur ini tidak diizinkan untuk dijelajahi: {path}",
      err_no_such_dir: "Direktori tidak ditemukan: {path}",
      err_lib_empty: "Pustaka animasi kosong",
      err_reset_failed: "Reset gagal",
      err_params_empty: "Parameter kosong",
      err_write_order_failed: "Gagal menulis urutan",
      err_save_order_failed: "Gagal menyimpan urutan",
      err_target_is_source: "Target adalah berkas pustaka itu sendiri",
      err_write_failed: "Gagal menulis: {path}",
      err_no_unzip: "Perangkat tidak memiliki unzip, tidak dapat mengekstrak frame",
      err_cannot_read_zip_dir: "Tidak dapat membaca direktori paket (zip mungkin rusak)",
      err_no_desc_in_pkg: "Paket tidak memiliki desc.txt",
      err_no_parts_in_desc: "Tidak ada bagian p/c di desc",
      err_no_previewable_frames: "Paket ini tidak memiliki frame yang dapat dipratinjau",
      err_cannot_create_pv_dir: "Tidak dapat membuat direktori pratinjau: {path}",
      err_cannot_decode_frames: "Frame tidak dapat didekode (gambar mungkin bukan PNG/JPG)",
      err_sync_deploy_failed: "Penyebaran sinkronisasi gagal"
    },
    "zh-CN": {
      // App header
      app_title: "开机动画管理器",
      app_sub: "换开机动画，重启生效",
      theme_group_aria: "主题风格",
      theme_auto: "跟随系统",
      theme_light: "浅色",
      theme_dark: "深色",
      lang_btn_aria: "选择语言",
      lang_modal_title: "选择语言",
      lang_active_tag: "使用中",
      theme_modal_title: "主题风格",
      theme_desc_auto: "跟随设备系统深浅色外观",
      theme_desc_light: "浅色主题",
      theme_desc_dark: "深色主题",
      toast_theme_changed: "主题已切换为{theme}",

      // Current Animation Card
      cur_title: "当前动画",
      cur_loading: "读取中…",
      cur_none: "无",
      cur_noanim: "已关闭开机动画：开机会直接进系统（库里的动画都还在）",
      cur_theme_ok: "已写入主题路径，重启生效 · {size}",
      cur_not_written: "还没写入，切个动画就会写",
      cur_path_lib: "库文件：{path}",
      cur_path_theme: "刷入位置：{path}",
      cur_path_screen: "本机屏幕：{screen}",

      // Library Card
      lib_title: "动画库",
      lib_meta: "{count} 个 · {size}",
      lib_empty: "动画库为空",
      lib_load_failed: "读取失败，点「刷新」重试",
      lib_hint: "点「应用」换动画，重启生效；正在用的那个删不掉。<br>点 <b>▶</b> 先看效果，不用重启、也不用先应用。<br>排序：按住左边的 <b>⠿</b> 拖动，或者用 <b>▲▼</b> 一格一格移。<br>选「不播放动画」就是开机黑屏，直接进系统。",
      drag_handle_title: "按住拖动排序",
      preview_btn_title: "预览（不用重启）",
      move_up_title: "上移",
      move_down_title: "下移",
      in_use_tag: "使用中",
      btn_apply: "应用",
      btn_applied: "已应用",
      btn_edit: "编辑",
      btn_delete: "删除",
      btn_confirm_delete: "确认删除?",

      // Toolbar
      btn_refresh: "刷新",
      btn_check: "体检",
      btn_browse: "选择文件",
      btn_collapse_list: "收起列表",
      btn_vid: "视频转换",

      // File Browser Card
      browse_title: "选择文件",
      browse_parent_dir: "⬆ 上一级",
      browse_folder: "文件夹",
      browse_vid_sub: "{size} · 视频可转开机动画",
      browse_btn_convert: "转换",
      browse_btn_import: "导入",
      browse_empty: "这个目录里没有子文件夹或 zip",
      browse_hint: "点文件夹进去翻，找到动画 zip 点右边的「导入」。<br>换目录用第一行的「⬆ 上一级」；再点一次「选择文件」收起，收起后再点从「下载」目录重新开始。",

      // Edit Modal
      res_modal_title: "编辑动画 · ",
      res_name_placeholder: "动画名称",
      btn_rename: "改名",
      res_hint: "改的是库里这份副本的 desc.txt；正在使用的动画改完会自动重新刷入。",
      btn_fit_screen: "自适应屏幕",
      btn_swap: "交换宽高",
      btn_export: "导出",
      res_custom_title: "自定义宽高",
      res_custom_sub: "保留原帧率，只改宽高",
      res_w_placeholder: "宽",
      res_h_placeholder: "高",
      btn_res_apply: "应用",
      btn_close: "关闭",
      res_reading: "读取中…",
      res_cur_res: "当前分辨率：",
      res_unknown: "未知",
      res_adapt_mode: "适配模式：",
      res_mode_manual: "手动（部署时不再自动适配，点「自适应屏幕」恢复）",
      res_mode_auto: "自动（部署时适配到屏幕）",
      res_frames: "帧数：{frames} 帧",
      res_dur: "时长约 {dur}",
      res_screen: "本机屏幕：{screen}",

      // Preview Modal
      pv_close_aria: "关闭预览",
      pv_preparing: "准备中…",
      pv_replay: "重播",
      pv_extracting: "正在抽帧…",
      pv_loading_frame: "载入帧 {current}/{total}…",
      pv_stride_note: "（每 {stride} 帧取 1）",
      pv_part_seg: "第 {si}/{count} 段",
      pv_loop_infinite: "无限循环",
      pv_loop_times: "第 {rep}/{loop} 遍",
      pv_noanim_note: " · 开机直接进系统",
      pv_no_playable_frames: "这个包没有能播放的帧",
      pv_failed: "预览失败",

      // Video to Animation Card
      vid_title: "视频转动画",
      vid_searching: "查找视频…",
      vid_reading_dir: "读取目录…",
      vid_browse_other: "📁 浏览其他目录",
      vid_browse_other_sub: "自己翻文件夹找视频",
      vid_btn_browse: "浏览",
      vid_btn_select: "选择",
      vid_btn_open: "打开",
      vid_empty_dir: "这个目录里没有视频或子文件夹",
      vid_fps_label: "帧率",
      vid_fps_sub: "抽帧节奏，默认 30（高帧率解码吃力）",
      vid_play_label: "播放方式",
      vid_play_sub: "自动 = 短视频循环播到进系统",
      vid_loop_auto: "自动",
      vid_loop_loop: "循环",
      vid_loop_once: "播一遍",
      vid_quality_label: "画质",
      vid_quality_sub: "标准 = 包更小、转换更快",
      vid_quality_high: "高画质",
      vid_quality_standard: "标准",
      vid_btn_start: "开始转换并导入",
      vid_hint: "选一个视频（默认列出「下载」和「影片」），转成动画包并自动导入动画库；<br>其他目录点「浏览其他目录」自己翻。画质：原生分辨率满屏、JPG 高质量；<br>帧数上限 600 帧，长视频建议先剪短；只取画面，不带声音。<br>格式需网页能解：MP4/H.264 最稳。<br>再点一次「视频转换」收起，收起后再点回到上次浏览的目录。",

      // Dynamic Video Conversion messages
      vid_prog_reading: "读取视频 {percent}%",
      vid_prog_detail: "视频 {vw}×{vh} {dur}s → {n} 帧 {fps}fps{loop}",
      vid_loop_tag: "（循环）",
      vid_once_tag: "（播一遍）",
      vid_prog_extracting: "抽帧 {i}/{n}",
      vid_prog_packing: "打包 zip…",
      vid_prog_writing: "写回 {percent}%",
      vid_prog_importing: "导入动画库…",
      vid_prog_done: "导入完成",
      vid_default_name: "视频转动画",

      // Built-in special animation names
      no_anim_name: "不播放动画",
      demo_anim_name: "演示动画",

      // Units
      bytes_unknown: "未知大小",

      // Toasts & Success/Info messages
      toast_order_saved: "排序已保存",
      toast_switched: "已切换到 {name}，重启后生效",
      toast_deleted: "已删除 {name}",
      toast_imported: "已导入 {name}",
      toast_exported: "已导出到 {path}",
      toast_name_empty: "名字不能为空",
      toast_name_too_long: "名字最长 60 个字",
      toast_renamed: "已改名为 {name}",
      toast_adapted: "已适配到本机屏幕",
      toast_swapped: "已交换宽高",
      toast_num_required: "宽和高都得是数字",
      toast_num_range: "宽高得在 100-16384 之间",
      toast_res_set: "已设为 {w}×{h}",
      toast_check_ok: "体检通过：{count} 个包都能正常播放",
      toast_check_bad: "{count} 个包有问题，例如 {detail}",
      toast_check_bad_simple: "{count} 个包有问题",
      toast_pick_video: "先选一个视频",
      toast_convert_done: "转换完成：{frames} 帧 {fps}fps，已导入 {stored}，重启生效",
      toast_lang_changed: "语言已切换为简体中文",

      // Client-side Errors & Fallbacks
      err_op_failed: "操作失败，请重试",
      err_op_failed_simple: "操作失败",
      err_no_ksu_list: "未检测到 KernelSU 模块接口，无法读取动画列表",
      err_no_ksu_root: "未检测到 KernelSU / SukiSU 的模块接口，请在模块管理器中打开本页面。",
      err_cmd_timeout: "命令执行超时",
      err_dir_read_failed: "读取目录失败",
      err_cannot_read_video: "读不到视频内容",
      err_video_too_large: "视频太大（{size}MB > {limit}MB），先剪短再转",
      err_video_incomplete: "视频读取不完整，请重试",
      err_write_verify_failed: "写回校验失败（{sz} ≠ {len}）",
      err_video_not_supported: "这个视频网页解不动（MP4/H.264 最稳，别的格式试试转 MP4）",
      err_video_read_timeout: "读取视频超时",
      err_video_invalid_info: "视频信息异常",
      err_no_frames_extracted: "没有抽到画面帧，已中止：视频可能解码异常，换个 MP4 再试",
      err_frame_timeout: "帧载入超时",
      err_frame_read_failed: "帧读不出来",

      // Backend ctl.sh Error Mappings
      err_anim_not_found: "找不到该动画，请刷新后重试",
      err_file_not_found: "找不到文件，可能已被移动或删除",
      err_file_empty_or_missing: "文件不存在或为空",
      err_not_valid_zip: "不是有效的 zip 文件",
      err_missing_desc: "zip 根目录缺少 desc.txt",
      err_desc_empty: "desc.txt 是空的",
      err_desc_bom: "desc.txt 带 UTF-8 BOM，会导致开机黑屏——请用无 BOM 的 UTF-8 重新保存",
      err_desc_not_standard: "desc.txt 首行不是「宽 高 帧率」格式",
      err_no_frames: "包里没有帧图片（只有 desc.txt，开机会黑屏）",
      err_bad_parts: "desc 里的段落目录不存在或没有帧：{badpart}（开机会黑屏）",
      err_zip_stored_required: "动画必须是 ZIP_STORED 无压缩格式",
      err_cannot_read_desc: "读不到 desc.txt",
      err_desc_format_invalid: "desc 不是标准格式",
      err_write_desc_failed: "写入 desc 失败",
      err_save_selection_failed: "保存选择失败",
      err_write_theme_failed: "动画已选择，但写入主题路径失败",
      err_cannot_read_screen: "读不到本机分辨率",
      err_adapt_failed: "适配失败：新分辨率串比原来的长，或 desc 不是标准格式",
      err_w_must_be_num: "宽必须是数字",
      err_h_must_be_num: "高必须是数字",
      err_digits_too_long: "宽高位数太长",
      err_range_invalid: "宽高超出合理范围（100-16384）",
      err_name_empty: "名字不能为空",
      err_name_invalid: "名字无效",
      err_name_dot_start: "名字不能以点开头（会变成隐藏文件，列表里看不到）",
      err_name_duplicate: "已有同名动画",
      err_rename_failed: "改名失败",
      err_no_file_specified: "未指定文件",
      err_copy_file_failed: "复制文件失败",
      err_anim_in_use: "该动画正在使用中，请先切换到其他动画",
      err_delete_failed: "删除失败",
      err_path_no_dots: "路径里不能带 ..：{path}",
      err_browse_not_allowed: "这个路径不让浏览：{path}",
      err_no_such_dir: "没有这个目录：{path}",
      err_lib_empty: "动画库为空",
      err_reset_failed: "重置失败",
      err_params_empty: "参数为空",
      err_write_order_failed: "无法写入排序",
      err_save_order_failed: "保存排序失败",
      err_target_is_source: "目标就是库里的文件本身",
      err_write_failed: "写入失败：{path}",
      err_no_unzip: "本机没有 unzip，没法抽帧",
      err_cannot_read_zip_dir: "读不了这个包的目录（zip 可能坏了）",
      err_no_desc_in_pkg: "包里没有 desc.txt",
      err_no_parts_in_desc: "desc 里没有 p/c 段落",
      err_no_previewable_frames: "这个包没有可预览的帧",
      err_cannot_create_pv_dir: "建不了预览目录：{path}",
      err_cannot_decode_frames: "帧解不出来（包里的图可能不是 PNG/JPG）",
      err_sync_deploy_failed: "同步部署失败"
    }
  };

  // Determine language:
  // Priority: 1. Manually saved language in localStorage
  //           2. Default to "en"
  let currentLang = "en";
  try {
    const saved = localStorage.getItem(LANG_KEY);
    if (saved && (saved === "en" || saved === "id" || saved === "zh-CN")) {
      currentLang = saved;
    }
  } catch (_) {
    currentLang = "en";
  }

  function t(key, params) {
    let str = (TRANSLATIONS[currentLang] && TRANSLATIONS[currentLang][key])
           || (TRANSLATIONS["en"] && TRANSLATIONS["en"][key])
           || (TRANSLATIONS["zh-CN"] && TRANSLATIONS["zh-CN"][key])
           || key;
    if (params && typeof params === "object") {
      for (const [k, v] of Object.entries(params)) {
        str = str.replace(new RegExp("\\{" + k + "\\}", "g"), v != null ? v : "");
      }
    }
    return str;
  }

  function setLanguage(lang) {
    if (!LANGUAGES[lang]) return;
    currentLang = lang;
    try {
      localStorage.setItem(LANG_KEY, lang);
    } catch (_) {}
    document.documentElement.setAttribute("lang", lang);
    updateDOM();
  }

  function getLanguage() {
    return currentLang;
  }

  function translateError(rawText) {
    const line = String(rawText || "").split(/\r?\n/).find(l => l.trim().startsWith("ERROR ")) || "";
    let m = line.replace(/^ERROR\s*/, "").trim();
    if (!m) return t("err_op_failed");

    // Match against known patterns
    if (/找不到该动画|invalid animation index/i.test(m)) return t("err_anim_not_found");
    if (/找不到文件[:：]?\s*(.+)/.test(m)) return t("err_file_not_found");
    if (/找不到文件/.test(m)) return t("err_file_not_found");
    if (/文件不存在或为空/.test(m)) return t("err_file_empty_or_missing");
    if (/不是有效的\s*zip\s*文件/.test(m)) return t("err_not_valid_zip");
    if (/zip\s*根目录缺少\s*desc\.txt/.test(m)) return t("err_missing_desc");
    if (/desc\.txt\s*是空的/.test(m)) return t("err_desc_empty");
    if (/desc\.txt\s*带\s*UTF-8\s*BOM/.test(m)) return t("err_desc_bom");
    if (/desc\.txt\s*首行不是/.test(m)) return t("err_desc_not_standard");
    if (/包里没有帧图片/.test(m)) return t("err_no_frames");
    let match = /desc\s*里的段落目录不存在或没有帧[：:]\s*(.+?)(?:[（(]开机会黑屏[）)])?$/.exec(m);
    if (match) return t("err_bad_parts", { badpart: match[1].trim() });
    if (/动画必须是\s*ZIP_STORED/.test(m)) return t("err_zip_stored_required");
    if (/读不到\s*desc\.txt/.test(m)) return t("err_cannot_read_desc");
    if (/desc\s*不是标准格式/.test(m)) return t("err_desc_format_invalid");
    if (/写入\s*desc\s*失败/.test(m)) return t("err_write_desc_failed");
    if (/保存选择失败/.test(m)) return t("err_save_selection_failed");
    if (/动画已选择，但写入主题路径失败/.test(m)) return t("err_write_theme_failed");
    if (/读不到本机分辨率/.test(m)) return t("err_cannot_read_screen");
    if (/适配失败/.test(m)) return t("err_adapt_failed");
    if (/宽必须是数字/.test(m)) return t("err_w_must_be_num");
    if (/高必须是数字/.test(m)) return t("err_h_must_be_num");
    if (/宽和高都得是数字/.test(m)) return t("toast_num_required");
    if (/宽高得在\s*100-16384\s*之间/.test(m)) return t("toast_num_range");
    if (/宽高位数太长/.test(m)) return t("err_digits_too_long");
    if (/宽高超出合理范围/.test(m)) return t("err_range_invalid");
    if (/名字不能为空/.test(m)) return t("err_name_empty");
    if (/名字无效/.test(m)) return t("err_name_invalid");
    if (/名字不能以点开头/.test(m)) return t("err_name_dot_start");
    if (/已有同名动画/.test(m)) return t("err_name_duplicate");
    if (/改名失败/.test(m)) return t("err_rename_failed");
    if (/未指定文件/.test(m)) return t("err_no_file_specified");
    if (/复制文件失败/.test(m)) return t("err_copy_file_failed");
    if (/该动画正在使用中/.test(m)) return t("err_anim_in_use");
    if (/删除失败/.test(m)) return t("err_delete_failed");
    match = /路径里不能带\s*\.\.[：:]\s*(.+)/.exec(m);
    if (match) return t("err_path_no_dots", { path: match[1] });
    match = /这个路径不让浏览[：:]\s*(.+)/.exec(m);
    if (match) return t("err_browse_not_allowed", { path: match[1] });
    match = /没有这个目录[：:]\s*(.+)/.exec(m);
    if (match) return t("err_no_such_dir", { path: match[1] });
    if (/动画库为空/.test(m)) return t("err_lib_empty");
    if (/重置失败/.test(m)) return t("err_reset_failed");
    if (/参数为空/.test(m)) return t("err_params_empty");
    if (/无法写入排序/.test(m)) return t("err_write_order_failed");
    if (/保存排序失败/.test(m)) return t("err_save_order_failed");
    if (/目标就是库里的文件本身/.test(m)) return t("err_target_is_source");
    match = /写入失败[：:]\s*(.+)/.exec(m);
    if (match) return t("err_write_failed", { path: match[1] });
    if (/本机没有\s*unzip/.test(m)) return t("err_no_unzip");
    if (/读不了这个包的目录/.test(m)) return t("err_cannot_read_zip_dir");
    if (/包里没有\s*desc\.txt/.test(m)) return t("err_no_desc_in_pkg");
    if (/desc\s*里没有\s*p\/c\s*段落/.test(m)) return t("err_no_parts_in_desc");
    if (/这个包没有可预览的帧/.test(m)) return t("err_no_previewable_frames");
    match = /建不了预览目录[：:]\s*(.+)/.exec(m);
    if (match) return t("err_cannot_create_pv_dir", { path: match[1] });
    if (/帧解不出来/.test(m)) return t("err_cannot_decode_frames");
    if (/sync=deploy-failed/.test(m)) return t("err_sync_deploy_failed");

    return m;
  }

  function updateDOM() {
    document.title = t("app_title");

    document.querySelectorAll("[data-i18n]").forEach(el => {
      const key = el.getAttribute("data-i18n");
      if (key) el.textContent = t(key);
    });

    document.querySelectorAll("[data-i18n-html]").forEach(el => {
      const key = el.getAttribute("data-i18n-html");
      if (key) el.innerHTML = t(key);
    });

    document.querySelectorAll("[data-i18n-placeholder]").forEach(el => {
      const key = el.getAttribute("data-i18n-placeholder");
      if (key) el.placeholder = t(key);
    });

    document.querySelectorAll("[data-i18n-title]").forEach(el => {
      const key = el.getAttribute("data-i18n-title");
      if (key) el.title = t(key);
    });

    document.querySelectorAll("[data-i18n-aria]").forEach(el => {
      const key = el.getAttribute("data-i18n-aria");
      if (key) el.setAttribute("aria-label", t(key));
    });

    // Notify listeners if registered
    if (typeof window.onLanguageChanged === "function") {
      try {
        window.onLanguageChanged(currentLang);
      } catch (_) {}
    }
  }

  // Export to window
  window.QIMU_I18N = {
    LANGUAGES,
    TRANSLATIONS,
    t,
    setLanguage,
    getLanguage,
    translateError,
    updateDOM
  };

  // Set early html lang attribute
  document.documentElement.setAttribute("lang", currentLang);
})();
