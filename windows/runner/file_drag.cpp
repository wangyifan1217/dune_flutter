#include "file_drag.h"

#include <ole2.h>
#include <shlobj.h>
#include <windows.h>

#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (len <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), len);
  if (!out.empty() && out.back() == L'\0') out.pop_back();
  return out;
}

HGLOBAL BuildHDrop(const std::vector<std::wstring>& paths) {
  size_t chars = 1;
  for (const auto& path : paths) {
    chars += path.size() + 1;
  }
  const size_t bytes = sizeof(DROPFILES) + chars * sizeof(wchar_t);
  HGLOBAL mem = GlobalAlloc(GHND, bytes);
  if (!mem) return nullptr;
  auto* drop = static_cast<DROPFILES*>(GlobalLock(mem));
  if (!drop) {
    GlobalFree(mem);
    return nullptr;
  }
  drop->pFiles = sizeof(DROPFILES);
  drop->fWide = TRUE;
  auto* dest = reinterpret_cast<wchar_t*>(reinterpret_cast<BYTE*>(drop) +
                                          sizeof(DROPFILES));
  for (const auto& path : paths) {
    memcpy(dest, path.c_str(), (path.size() + 1) * sizeof(wchar_t));
    dest += path.size() + 1;
  }
  *dest = L'\0';
  GlobalUnlock(mem);
  return mem;
}

class DropSource final : public IDropSource {
 public:
  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&ref_);
  }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG n = InterlockedDecrement(&ref_);
    if (n == 0) delete this;
    return n;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (riid == IID_IUnknown || riid == IID_IDropSource) {
      *ppv = static_cast<IDropSource*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape,
                                              DWORD keys) override {
    if (escape) return DRAGDROP_S_CANCEL;
    if ((keys & MK_LBUTTON) == 0) return DRAGDROP_S_DROP;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override {
    return DRAGDROP_S_USEDEFAULTCURSORS;
  }

 private:
  LONG ref_ = 1;
};

class FileDataObject final : public IDataObject {
 public:
  explicit FileDataObject(std::vector<std::wstring> paths)
      : paths_(std::move(paths)) {}

  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&ref_);
  }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG n = InterlockedDecrement(&ref_);
    if (n == 0) delete this;
    return n;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (riid == IID_IUnknown || riid == IID_IDataObject) {
      *ppv = static_cast<IDataObject*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* fmt,
                                    STGMEDIUM* medium) override {
    if (!fmt || !medium) return E_INVALIDARG;
    if (fmt->cfFormat != CF_HDROP || !(fmt->tymed & TYMED_HGLOBAL)) {
      return DV_E_FORMATETC;
    }
    HGLOBAL mem = BuildHDrop(paths_);
    if (!mem) return E_OUTOFMEMORY;
    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = mem;
    medium->pUnkForRelease = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* fmt) override {
    if (!fmt) return E_INVALIDARG;
    if (fmt->cfFormat == CF_HDROP && (fmt->tymed & TYMED_HGLOBAL)) return S_OK;
    return DV_E_FORMATETC;
  }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*,
                                                  FORMATETC* out) override {
    if (out) out->ptd = nullptr;
    return DATA_E_FORMATETC;
  }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD dir,
                                          IEnumFORMATETC** pp) override {
    if (!pp) return E_INVALIDARG;
    if (dir != DATADIR_GET) return E_NOTIMPL;
    FORMATETC fmt{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    return SHCreateStdEnumFmtEtc(1, &fmt, pp);
  }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*,
                                    DWORD*) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

 private:
  std::vector<std::wstring> paths_;
  LONG ref_ = 1;
};

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

void StartFileDrag(const flutter::EncodableValue* arguments,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                       result) {
  std::vector<std::wstring> paths;
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map) {
    const auto it = map->find(flutter::EncodableValue("paths"));
    if (it != map->end()) {
      if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
        for (const auto& item : *list) {
          if (const auto* utf8 = std::get_if<std::string>(&item)) {
            std::wstring wide = Utf8ToWide(*utf8);
            if (!wide.empty() && GetFileAttributesW(wide.c_str()) !=
                                     INVALID_FILE_ATTRIBUTES) {
              paths.push_back(std::move(wide));
            }
          }
        }
      }
    }
  }
  if (paths.empty()) {
    result->Error("no_file", "没有可拖出的本地文件");
    return;
  }

  OleInitialize(nullptr);
  auto* data = new FileDataObject(std::move(paths));
  auto* source = new DropSource();
  DWORD effect = DROPEFFECT_NONE;
  DoDragDrop(data, source, DROPEFFECT_COPY, &effect);
  data->Release();
  source->Release();
  result->Success();
}

}  // namespace

void RegisterDesktopFileDragChannel(flutter::BinaryMessenger* messenger) {
  if (!messenger) return;
  g_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "nova.dunes/desktop_file_drag",
          &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "start") {
          StartFileDrag(call.arguments(), std::move(result));
          return;
        }
        result->NotImplemented();
      });
}
