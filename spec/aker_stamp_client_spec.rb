require "spec_helper"
require "pry"

RSpec.describe StampClient do

  let(:content_type) { 'application/vnd.api+json' }
  let(:request_headers) { { 'Accept' => content_type, 'Content-Type'=> content_type } }
  let(:response_headers) { { 'Content-Type' => content_type } }
  let(:url) { 'http://localhost:9999/api/v1/' }

  before do
    StampClient::Base.site = url
  end

  it "has a version number" do
    expect(AkerStampClient::VERSION).not_to be nil
  end

  describe StampClient::Stamp do

    describe "#create" do
      before do
        @new_id = SecureRandom.uuid
        @name = "stamp4"
        @owner = "guest"
        stub_request(:post, url+"stamps")
          .with( body: { data: { type: "stamps", attributes: { name: "stamp4" }}}.to_json, headers: request_headers )
          .to_return(status: 201, body: { data: make_stamp_data(@new_id, @name, @owner) }.to_json, headers: response_headers)

        @new_stamp = StampClient::Stamp.create({name: 'stamp4'})
      end

      it "has an id" do
        expect(@new_stamp.id).to eq(@new_id)
      end

      it "has a name" do
        expect(@new_stamp.name).to eq(@name)
      end

      it "has an owner" do
        expect(@new_stamp.owner_id).to eq(@owner)
      end
    end

    describe '#find' do
      before do
        @id = SecureRandom.uuid
        @name = "stamp1"
        @owner_id = "jeff"

        stub_stamp(@id, @name, @owner_id)

        @rs = StampClient::Stamp.find(@id)
        @stamp = @rs&.first
      end

      it 'finds one stamp' do
        expect(@rs).not_to be_nil
        expect(@rs.length).to eq(1)
      end

      it 'gives a stamp with the correct fields' do
        expect(@stamp).not_to be_nil
        expect(@stamp.id).to eq(@id)
        expect(@stamp.name).to eq(@name)
        expect(@stamp.owner_id).to eq(@owner_id)
      end
    end

    describe '#all' do
      before do
        @data = [
          make_stamp_data(SecureRandom.uuid, "stamp1", 'jeff'),
          make_stamp_data(SecureRandom.uuid, "stamp2", 'bob'),
        ]
        stub_request(:get, url+'stamps')
          .to_return(status: 200, body: { data: @data }.to_json, headers: response_headers)
      end

      it 'returns all stamps' do
        rs = StampClient::Stamp.all
        expect(rs.length).to eq(@data.length)
        @data.zip(rs).each do |d, stamp|
          expect(stamp.id).to eq(d[:id])
          expect(stamp.name).to eq(d[:attributes][:name])
          expect(stamp.owner_id).to eq(d[:attributes][:'owner-id'])
        end
      end
    end

    describe '#update' do
      before do
        id = SecureRandom.uuid
        name = "stamp1"
        owner_id = "jeff"
        @newname = 'newname'

        stub_stamp(id, name, owner_id)

        rs = StampClient::Stamp.find(id)
        @stamp = rs&.first

        stub_request(:patch, stamp_urlid(id))
          .with( body: { data: { id: id, type: "stamps", attributes: { name: @newname}}}.to_json, headers: request_headers)
          .to_return(status: 200, body: { data: make_stamp_data(id, @newname, owner_id) }.to_json, headers: response_headers)
      end

      it "can be updated" do
        @stamp.update(name: @newname)
        expect(WebMock).to have_requested(:patch, stamp_urlid(@stamp.id)).
          with( body: { data: { id: @stamp.id, type: "stamps", attributes: { name: @newname }}}.to_json, headers: request_headers)
        expect(@stamp.name).to eq @newname
      end
    end

    describe '#find_with_permissions' do
      before do
        @stamp_id = SecureRandom.uuid
        @name = "stamp1"
        @owner_id = "dirk@here.com"

        stub_stamp(@stamp_id, @name, @owner_id)
      end

      it "returns an empty list when the stamp has no permissions" do
        response_body = make_stamp_with_no_permission_data(@stamp_id, @name, @owner_id)

        stub_request(:get, stamp_urlid(@stamp_id)+"?include=permissions")
          .with(headers: request_headers )
          .to_return(status: 200, body: response_body.to_json, headers: response_headers)

        stamp = StampClient::Stamp.find_with_permissions(@stamp_id)
        expect(stamp).not_to be_nil
        permissions = stamp.first.permissions
        expect(permissions.length).to eq 0
        expect(permissions).to eq []
      end

      it "returns list of permissions when the stamp has permissions" do
        @permission_id = "1"
        @permission_type = :spend
        @permitted = 'zogh'

        response_body = make_stamp_with_permission_data(@stamp_id, @name, @owner_id, @permission_id, @permitted, @permission_type)

        stub_request(:get, stamp_urlid(@stamp_id)+"?include=permissions")
          .with(headers: request_headers )
          .to_return(status: 200, body: response_body.to_json, headers: response_headers)

        stamp = StampClient::Stamp.find_with_permissions(@stamp_id)
        permissions = stamp.first.permissions
        expect(permissions).not_to be_nil
        expect(permissions.length).to eq 1
        permission = permissions&.first
        expect(permission.id).to eq @permission_id
        expect(permission.permission_type).to eq @permission_type
        expect(permission.permitted).to eq @permitted
        expect(permission.accessible_id).to eq @stamp_id
      end
    end

    describe '#set_permissions' do
      before do
        @stamp_id = SecureRandom.uuid
        @name = "stamp1"
        @owner_id = "dirk@here.com"

        @permission_id = "1"
        @permission_type = :spend
        @permitted = 'zogh'

        stub_stamp(@stamp_id, @name, @owner_id)
      end

      context 'when the user is the owner of the stamp' do
        it 'sets the permissions on the stamp' do
          stamp = StampClient::Stamp.find(@stamp_id).first
          permissions = [{ permission_type: @permission_type, permitted: @permitted}]
          stub_data = { data: [ 'permission-type': @permission_type, permitted: @permitted] }

          response_body = make_stamp_with_permission_data(@stamp_id, @name, @owner_id, @permission_id, @permitted, @permission_type)

          stub_request(:post, stamp_urlid(@stamp_id)+"/set_permissions")
            .with(body: stub_data.to_json, headers: request_headers)
            .to_return(status: 200, body: response_body.to_json, headers: response_headers)

          permissions = stamp.set_permissions_to(permissions).permissions

          expect(WebMock).to have_requested(:post, stamp_urlid(@stamp_id)+"/set_permissions")
            .with(body: stub_data.to_json, headers: request_headers)

          expect(permissions).not_to be_nil
          expect(permissions.length).to eq 1
          permission = permissions&.first
          expect(permission.id).to eq "1"
          expect(permission.permission_type).to eq @permission_type
          expect(permission.permitted).to eq @permitted
          expect(permission.accessible_id).to eq @stamp_id
        end
      end

      context 'when the user is not the owner of the stamp' do
        it 'raises an error' do
          stamp = StampClient::Stamp.find(@stamp_id).first
          permissions = [{ permission_type: @permission_type , permitted: @permitted}]
          stub_data = { data: [ 'permission-type': @permission_type, permitted: @permitted] }

          stub_request(:post, stamp_urlid(@stamp_id)+"/set_permissions")
            .with(body: stub_data.to_json, headers: request_headers)
            .to_return(status: 403, body: "", headers: response_headers)

          expect { stamp.set_permissions_to(permissions) }.to raise_error JsonApiClient::Errors::AccessDenied
        end
      end
    end

    describe '#apply' do
      before do
        @stamp_id = SecureRandom.uuid
        @name = "stamp1"
        @owner_id = "jeff"

        stub_stamp(@stamp_id, @name, @owner_id)
      end

      context 'when the user is the owner of the material to be stamped' do
        it 'stamps the material' do
          material_id = 1
          material_uuid = SecureRandom.uuid
          stamp = StampClient::Stamp.find(@stamp_id).first
          materials = [material_uuid]
          stub_data = { data: { materials: materials } }

          response_body = make_stamp_with_material_data(@stamp_id, @name, @owner_id, material_id, material_uuid)

          stub_request(:post, stamp_urlid(@stamp_id)+"/apply")
            .with(body: stub_data.to_json, headers: request_headers)
            .to_return(status: 200, body: response_body.to_json, headers: response_headers)

          stamp = stamp.apply_to(materials)

          expect(WebMock).to have_requested(:post, stamp_urlid(@stamp_id)+"/apply")
            .with(body: stub_data.to_json, headers: request_headers)

          expect(stamp).not_to be be_nil
          expect(stamp.materials.first.stamp_id).to eq @stamp_id
        end
      end

      context 'when the user is not the owner of the material to be stamped' do
        it 'raises an error' do
          material_uuid = SecureRandom.uuid
          stamp = StampClient::Stamp.find(@stamp_id).first
          materials = [material_uuid]
          stub_data = { data: { materials: materials }}

          stub_request(:post, stamp_urlid(@stamp_id)+"/apply")
            .with(body: stub_data.to_json, headers: request_headers)
            .to_return(status: 403, body: "", headers: response_headers)

          expect{stamp.apply_to(materials)}.to raise_error JsonApiClient::Errors::AccessDenied
        end
      end
    end

    describe '#unapply' do
      before do
        @stamp_id = SecureRandom.uuid
        @name = "stamp1"
        @owner_id = "jeff"
        @material_id = 1
        @material_uuid = SecureRandom.uuid

        stamp_data = make_stamp_with_material_data(@stamp_id, @name, @owner_id, @material_id, @material_uuid)

        stub_request(:get, stamp_urlid(@stamp_id))
          .with(headers: request_headers)
          .to_return(status: 200, body: stamp_data.to_json, headers: response_headers)
      end

      context 'when the user is the owner of the material to be unstamped' do
        it 'removes the stamp on the material' do
          stamp = StampClient::Stamp.find(@stamp_id).first
          material_uuid = stamp.materials.first.material_uuid
          materials = [material_uuid]
          stub_data = { data: { materials: materials } }

          expect(material_uuid).to eq @material_uuid

          response_body = make_stamp_with_no_material_data(@stamp_id, @name, @owner_id)

          stub_request(:post, stamp_urlid(@stamp_id)+"/unapply")
            .with(body: stub_data.to_json, headers: request_headers)
            .to_return(status: 200, body: response_body.to_json, headers: response_headers)

          stamp = stamp.unapply_to(materials)

          expect(WebMock).to have_requested(:post, stamp_urlid(@stamp_id)+"/unapply")
            .with(body: stub_data.to_json, headers: request_headers)

          expect(stamp).not_to be be_nil
          expect(stamp.materials).to eq []
        end
      end

      context 'when the user is not the owner of the material to be unstamped' do
        it 'raises an error' do
          stamp = StampClient::Stamp.find(@stamp_id).first
          material_uuid = stamp.materials.first["material-uuid"]
          materials = [material_uuid]
          stub_data = { data: { materials: materials } }

          stub_request(:post, stamp_urlid(@stamp_id)+"/unapply")
            .with(body: stub_data.to_json, headers: request_headers)
            .to_return(status: 403, body: "", headers: response_headers)

          expect { stamp.unapply_to(materials) }.to raise_error JsonApiClient::Errors::AccessDenied
        end
      end

    end
  end

  describe StampClient::Permission do
    describe '#create' do
      before do
        @id = SecureRandom.uuid
        stamp_name = 'stamp123'
        stamp_owner_id = 'dirk@here.com'
        stub_stamp(@id, stamp_name, stamp_owner_id)

        rs = StampClient::Stamp.find(@id)
        @stamp = rs&.first

        @permission_type = :spend
        @permitted = 'permitted_person'
        @postdata = { type: "permissions", attributes: { "permission-type": @permission_type, permitted: @permitted, "accessible-id": @id }}
      end

      context 'when the user is the owner of the stamp' do
        before do
          @permission_id = "4"
          response_body = make_permission_data(@permission_id, @permission_type, @permitted, @id)

          stub_request(:post, url+"permissions")
            .with(body: { data: @postdata }.to_json, headers: request_headers)
            .to_return(status: 200, body: response_body.to_json, headers: response_headers)
        end

        it 'creates a permission on the stamp' do
          perm = StampClient::Permission.create(permission_type: @permission_type, permitted: @permitted, accessible_id: @id)

          expect(WebMock).to have_requested(:post, url+"permissions")
            .with(body: { data: @postdata }.to_json, headers: request_headers)

          expect(perm).not_to be_nil
          expect(perm.id).to eq @permission_id
          expect(perm.permission_type).to eq @permission_type
          expect(perm.permitted).to eq @permitted
          expect(perm.accessible_id).to eq @id
        end
      end

      context 'when the user is not the owner of the stamp' do
        before do
          stub_request(:post, url+"permissions")
            .with(body: { data: @postdata }.to_json, headers: request_headers)
            .to_return(status: 403, body: "", headers: response_headers)
        end

        it 'throws AccessDenied exception' do
          expect { StampClient::Permission.create(permission_type: @permission_type, permitted: @permitted, accessible_id: @id) }.to raise_error JsonApiClient::Errors::AccessDenied
        end
      end
    end

    describe '#destroy' do

      context 'when the user is the owner of the stamp' do
        before do
          @id = "1"
          permission_type = :spend
          permitted = 'dirk'
          stamp_id = SecureRandom.uuid
          stub_permission(@id, permission_type, permitted, stamp_id)

          stub_request(:delete, url+"permissions").
            with(headers: response_headers).
            to_return(status: 204, body: "", headers: response_headers)
        end

        it 'deletes the permission' do
          perm = StampClient::Permission.find(@id).first
          expect(perm.destroy).to eq true
          expect(WebMock).to have_requested(:delete, url+"permissions")
        end
      end

      context 'when the user is not the owner of the stamp' do
        before do
          @perm_id = "1"
          permission_type = :spend
          permitted = 'dirk'
          stamp_id = SecureRandom.uuid
          stub_permission(@perm_id, permission_type, permitted, stamp_id)

          stub_request(:delete, url+"permissions").
            with(headers: response_headers).
            to_return(status: 403, body: "", headers: {})
        end

        it 'raises an error' do
          perm = StampClient::Permission.find(@perm_id).first
          expect { perm.destroy }.to raise_error JsonApiClient::Errors::AccessDenied
        end
      end

    end

    describe '#check_catch' do
      before do
        @permission_type = :spend
        @names = ['dirk@here.com']
        @material_uuids = [ SecureRandom.uuid, SecureRandom.uuid, SecureRandom.uuid ]
      end

      context 'when there are no unpermitted material uuids' do
        before do
          stub_permission_check_200(@permission_type, @names, @material_uuids)
          @data = make_permission_check_data(@permission_type, @names, @material_uuids)
          @result = StampClient::Permission.check_catch(@data)
        end

        it 'sends the check request' do
          expect(WebMock).to have_requested(:post, url+"permissions/check")
            .with(body: { data: @data }.to_json, headers: request_headers)
        end

        it 'returns true' do
          expect(@result).to be_truthy
        end
      end

      context 'when there are unpermitted material uuids' do
        before do
          @unpermitted_uuid = @material_uuids[0,2]
          stub_permission_check_403(@permission_type, @names, @material_uuids, @unpermitted_uuids)
          data = make_permission_check_data(@permission_type, @names, @material_uuids)
          @result = StampClient::Permission.check_catch(data)
        end

        it 'returns false' do
          expect(@result).to be_falsey
        end

        it 'contains the unpermitted uuids' do
          expect(StampClient::Permission.unpermitted_uuids).to eq(@unpermitted_uuids)
        end
      end
    end

  end

  private

  def stamp_urlid(id)
    url+'stamps/'+id
  end

  def stub_stamp(id, name, owner_id)
    stamp_data = make_stamp_data(id, name, owner_id)

    stub_request(:get, stamp_urlid(id))
         .with(headers: request_headers)
         .to_return(status: 200, body: { data: stamp_data }.to_json, headers: response_headers)
  end

  def make_stamp_data(id, name, owner_id)
      {
        id: id,
        type: "stamps",
        attributes: {
          name: name,
          'owner-id': owner_id
        }
      }
  end

  def make_stamp_with_permission_data(id, name, owner_id, permission_id, permitted, permission_type)
    {
      data:
      {
        id: id,
        type: "stamps",
        attributes:
        {
          name: name,
          "owner-id": owner_id
        },
        relationships:
        {
          permissions:
          {
            data: [{ type: "permissions", id: permission_id}]
          }
        }
      },
      included:
      [
        {
          id: permission_id,
          type: "permissions",
          attributes:
          {
            "permission-type": permission_type,
            permitted: permitted,
            "accessible-id": id
          }
        }
      ]
    }
  end

  def make_stamp_with_no_permission_data(id, name, owner_id)
    {
      data:
      {
        id: id,
        type: "stamps",
        attributes:
        {
          name: name,
          "owner-id": owner_id
        },
        relationships:
        {
          permissions:
          {
            data: []
          }
        }
      }
    }
  end

  def make_stamp_with_material_data(id, name, owner_id, material_id, material_uuid)
    {
      data:
      {
        id: id,
        type: "stamps",
        attributes:
        {
          name: name,
          "owner-id": owner_id
        },
        relationships:
        {
          materials:
          {
            data: [{ type: "materials", id: material_id}]
          }
        }
      },
      included:
      [
        {
          id: material_id,
          type: "materials",
          attributes:
          {
            "material-uuid": material_uuid,
            "stamp-id": id
          }
        }
      ]
    }
  end

  def make_stamp_with_no_material_data(id, name, owner_id)
    {
      data:
      {
        id: id,
        type: "stamps",
        attributes:
        {
          name: name,
          "owner-id": owner_id
        },
        relationships:
        {
          materials:
          {
            data: []
          }
        }
      }
    }
  end

  def permission_urlid(id)
    url+'permissions/'+id
  end

  def stub_permission(id, permission_type, permitted, accessible_id)
    permission_data = make_permission_data(id, permission_type, permitted, accessible_id)

    stub_request(:get, permission_urlid(id))
        .with(headers: request_headers)
        .to_return(status: 200, body: { data: permission_data }.to_json, headers: response_headers)
  end

  def make_permission_data(id, permission_type, permitted, accessible_id)
    {
      data:
      {
        id: id,
        type: "permissions",
        attributes:
        {
          "permission-type": permission_type,
          permitted: permitted,
          "accessible-id": accessible_id
        }
      }
    }

  end

  def stub_permission_check_200(permission_type, names, material_uuids)
    data = make_permission_check_data(permission_type, names, material_uuids)
    stub_data = {data: data}
    stub_request(:post, url+"permissions/check").
      with(body: stub_data.to_json, headers: request_headers).
      to_return(status: 200, body: '', headers: response_headers)
  end

  def stub_permission_check_403(permission_type, names, material_uuids, unpermitted_uuids)
    data = make_permission_check_data(permission_type, names, material_uuids)
    stub_data = {data: data}

    response_body = { errors: [{
        status: "403",
        title: "Permission failed",
        detail: "The specified permission was not present for some materials.",
        material_uuids: unpermitted_uuids
    }]}

    stub_request(:post, url+"permissions/check").
      with(body: stub_data.to_json, headers: request_headers).
      to_return(status: 403, body: response_body.to_json, headers: response_headers)
  end

  def make_permission_check_data(permission_type, names, material_uuids)
    {
        permission_type: permission_type,
        names: names,
        material_uuids: material_uuids
    }
  end

end

