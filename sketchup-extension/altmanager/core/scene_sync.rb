# Sayou Alt Manager - Sync Camera
# 현재 뷰(카메라) 값을 등록된 모든 Alt Scene에 일괄 반영한다.

module SayouAltManager
  module SceneSync
    module_function

    def sync_camera(data)
      model = Sketchup.active_model
      source_camera = model.active_view.camera

      model.start_operation('Alt Manager - Sync Camera', true)
      begin
        data['topics'].each do |topic|
          topic['alts'].each do |alt|
            page = model.pages[alt['scene']]
            next unless page

            page.camera = clone_camera(source_camera)
          end
        end
        model.commit_operation
        { 'ok' => true }
      rescue StandardError => e
        model.abort_operation
        { 'ok' => false, 'error' => e.message }
      end
    end

    # 같은 Camera 인스턴스를 여러 Scene에 공유하면 한쪽을 바꿀 때 다른 Scene도
    # 같이 바뀌는 참조 공유 문제가 생기므로 Scene마다 새 Camera로 복제한다.
    def clone_camera(cam)
      new_cam = Sketchup::Camera.new(cam.eye, cam.target, cam.up)
      new_cam.perspective = cam.perspective?
      new_cam.fov = cam.fov if cam.perspective?
      new_cam.aspect_ratio = cam.aspect_ratio if cam.aspect_ratio && cam.aspect_ratio > 0
      new_cam
    end
  end
end
